#!/usr/bin/env bash
#
# One command: build the dbt image, deploy it to Kubernetes, run the project
# against your warehouse, and serve the docs UI.
#
#   cp .env.example .env   # point at your warehouse once
#   ./spinup.sh
#   ./spinup.sh --no-browser   # don't open a browser tab
#   ./spinup.sh --yes          # don't prompt before creating a missing database
#
# dbt runs in the cluster; the warehouse stays wherever it already is. If that
# is a server on this Mac, the script rewrites localhost to a hostname the pod
# can actually reach.
#
# Stop with Ctrl-C (the pod keeps running). Remove it with ./teardown.sh
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
PROJECT_ROOT="$PWD"

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m==>\033[0m %s\n' "$*"; }
error() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

OPEN_BROWSER=true
ASSUME_YES=false
for arg in "$@"; do
  case "$arg" in
    --no-browser) OPEN_BROWSER=false ;;
    --yes|-y)     ASSUME_YES=true ;;
    *) error "Unknown option: $arg (try --no-browser, --yes)" ;;
  esac
done

DOCS_URL="http://localhost:8080"
NAMESPACE=data
SECRET_NAME=dbt-warehouse
ENV_FILE="$PROJECT_ROOT/.env"

# --- Prerequisites ----------------------------------------------------------
ensure_brew() {
  command -v brew >/dev/null 2>&1 && return 0
  error "Homebrew is required to auto-install tools. Install it from https://brew.sh then re-run."
}

ensure_tool() {
  local bin="$1" pkg="${2:-$1}"
  command -v "$bin" >/dev/null 2>&1 && return 0
  info "$bin not found — installing via Homebrew..."
  ensure_brew
  brew install "$pkg"
}

ensure_tool docker         # Docker CLI (Docker Desktop provides the daemon)
ensure_tool kubectl
ensure_tool helm
ensure_tool skaffold

docker info >/dev/null 2>&1 || error "Docker daemon not reachable. Start Docker Desktop and try again."
kubectl cluster-info >/dev/null 2>&1 || \
  error "No reachable Kubernetes cluster. Enable Kubernetes in Docker Desktop (Settings > Kubernetes), or start minikube."

KUBE_CONTEXT="$(kubectl config current-context)"
info "Tooling and cluster OK. Context: $KUBE_CONTEXT"

# The project is mounted into the pod by hostPath, so the cluster VM has to be
# able to see this directory. Docker Desktop shares /Users by default and not
# much else — a repo in /tmp mounts as "not a directory" and the pod hangs in
# ContainerCreating, which is a slow way to learn this.
case "$(uname -s)" in
  Darwin)
    case "$PROJECT_ROOT" in
      /Users/*|/Volumes/*) ;;
      *) warn "This project lives at $PROJECT_ROOT."
         warn "Docker Desktop shares /Users and /Volumes by default; other paths"
         warn "fail to mount and the pod hangs in ContainerCreating."
         warn "Move the repo under your home directory, or add this path in"
         warn "Docker Desktop > Settings > Resources > File Sharing."
         if [[ "$ASSUME_YES" != true && -t 0 ]]; then
           printf '\033[1;33m==>\033[0m Continue anyway? [y/N] '
           read -r reply
           [[ "$reply" =~ ^[Yy] ]] || exit 1
         fi ;;
    esac ;;
esac

[[ -f "$ENV_FILE" ]] || error "No .env found. Run: cp .env.example .env — then fill in your warehouse."

set -a; . "$ENV_FILE"; set +a
TARGET="${DBT_TARGET:-postgres}"
info "Warehouse target: $TARGET"

# --- A warehouse on this Mac needs a different hostname inside the cluster ---
# In a pod, "localhost" is the pod itself. Docker Desktop and minikube each
# publish a DNS name that resolves to the host machine; use whichever applies.
host_gateway() {
  case "$KUBE_CONTEXT" in
    *minikube*) echo "host.minikube.internal" ;;
    *)          echo "host.docker.internal" ;;
  esac
}

is_loopback() {
  [[ "$1" == "localhost" || "$1" == "127.0.0.1" || "$1" == "::1" ]]
}

# Warn early if the server is bound to loopback only: the pod will not be able
# to reach it however we spell the hostname.
check_reachable_from_container() {
  local port="$1"
  command -v lsof >/dev/null 2>&1 || return 0
  local addrs
  addrs="$(lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $9}')"
  [[ -n "$addrs" ]] || return 0
  if ! grep -qvE '^(127\.0\.0\.1|\[::1\]):' <<<"$addrs"; then
    warn "The server on port $port is listening on loopback only:"
    sed 's/^/      /' <<<"$addrs" >&2
    cat >&2 <<MSG

    A pod cannot reach that, whatever hostname it uses. To open it up, in
    postgresql.conf set:

        listen_addresses = '*'

    and add a line to pg_hba.conf allowing the Docker network, e.g.

        host  all  all  192.168.65.0/24  scram-sha-256

    then restart Postgres. (Postgres.app: Server Settings > Show config files.)

MSG
    if [[ "$ASSUME_YES" != true && -t 0 ]]; then
      printf '\033[1;33m==>\033[0m Continue anyway? [y/N] '
      read -r reply
      [[ "$reply" =~ ^[Yy] ]] || exit 1
    fi
  fi
}

REWRITTEN_HOST=""
case "$TARGET" in
  postgres)
    if is_loopback "${DBT_PG_HOST:-localhost}"; then
      REWRITTEN_HOST="$(host_gateway)"
      check_reachable_from_container "${DBT_PG_PORT:-5432}"
      info "Warehouse is on this Mac — the pod will reach it at $REWRITTEN_HOST"
    fi ;;
  redshift)
    if is_loopback "${DBT_REDSHIFT_HOST:-localhost}"; then
      REWRITTEN_HOST="$(host_gateway)"
      check_reachable_from_container "${DBT_REDSHIFT_PORT:-5439}"
      info "Warehouse is on this Mac — the pod will reach it at $REWRITTEN_HOST"
    fi ;;
esac

# --- dbt creates schemas, never databases -----------------------------------
# On a server you own, offer to create a missing database so the first run is
# still one command. Cloud warehouses are left alone.
ensure_database() {
  case "$TARGET" in postgres|redshift) ;; *) return 0 ;; esac
  command -v psql >/dev/null 2>&1 || return 0

  local host port user password dbname
  if [[ "$TARGET" == postgres ]]; then
    host="${DBT_PG_HOST:-localhost}"; port="${DBT_PG_PORT:-5432}"
    user="${DBT_PG_USER:-dbt}"; password="${DBT_PG_PASSWORD:-}"
    dbname="${DBT_PG_DATABASE:-analytics}"
  else
    host="${DBT_REDSHIFT_HOST:-localhost}"; port="${DBT_REDSHIFT_PORT:-5439}"
    user="${DBT_REDSHIFT_USER:-dbt}"; password="${DBT_REDSHIFT_PASSWORD:-}"
    dbname="${DBT_REDSHIFT_DATABASE:-analytics}"
  fi

  # Reach the server on a database that is always there. If we cannot, say
  # nothing: the pod's own connection check reports credential problems better.
  local maintenance="" candidate
  for candidate in postgres dev "$user"; do
    if PGPASSWORD="$password" psql -h "$host" -p "$port" -U "$user" -d "$candidate" \
         -tAc 'select 1' >/dev/null 2>&1; then
      maintenance="$candidate"; break
    fi
  done
  [[ -n "$maintenance" ]] || return 0

  PGPASSWORD="$password" psql -h "$host" -p "$port" -U "$user" -d "$maintenance" -tAc \
    "select 1 from pg_database where datname = '$dbname'" 2>/dev/null | grep -q 1 && return 0

  if [[ "$ASSUME_YES" != true ]]; then
    [[ -t 0 ]] || error "Database '$dbname' does not exist on $host:$port. Create it, or re-run with --yes."
    printf '\033[1;33m==>\033[0m Database %s does not exist on %s:%s. Create it? [y/N] ' \
      "'$dbname'" "$host" "$port"
    read -r reply
    [[ "$reply" =~ ^[Yy] ]] || error "Not created. Create the database, then re-run."
  fi

  info "Creating database '$dbname'..."
  PGPASSWORD="$password" createdb -h "$host" -p "$port" -U "$user" "$dbname" \
    || error "Could not create '$dbname' — you may lack CREATEDB permission."
}

ensure_database

# --- Credentials into the cluster -------------------------------------------
# .env becomes a Secret the pod reads with envFrom, so credentials stay out of
# the chart, out of `helm get values`, and out of git.
info "Publishing warehouse credentials to Secret '$SECRET_NAME' in '$NAMESPACE'..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

SECRET_ENV="$ENV_FILE"
if [[ -n "$REWRITTEN_HOST" ]]; then
  # Same .env, with the host swapped for one the pod can resolve. Written with
  # a restrictive umask and removed on exit — it holds your credentials.
  SECRET_ENV="$(umask 077; mktemp "${TMPDIR:-/tmp}/dbt-env.XXXXXX")"
  trap 'rm -f "$SECRET_ENV"' EXIT
  # Delimiter is #, not |, because the pattern itself uses | for alternation.
  sed -E "s#^(DBT_(PG|REDSHIFT)_HOST)=.*#\1=$REWRITTEN_HOST#" "$ENV_FILE" > "$SECRET_ENV"
fi

kubectl create secret generic "$SECRET_NAME" --namespace "$NAMESPACE" \
  --from-env-file="$SECRET_ENV" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# --- Deploy -----------------------------------------------------------------
cat <<EOF

Building the dbt image and deploying via Skaffold...
The pod checks the warehouse connection, runs seed -> run -> test, then serves
the docs. Once ready (the browser opens on its own):
  dbt docs : $DOCS_URL
Press Ctrl-C to stop the port-forward.

EOF

# Poll the docs site and open it once it answers, rather than guessing a delay.
if [[ "$OPEN_BROWSER" == true ]] && command -v open >/dev/null 2>&1; then
  ( for _ in $(seq 1 180); do
      curl -sf -o /dev/null "$DOCS_URL" && { open "$DOCS_URL"; break; }
      sleep 2
    done ) >/dev/null 2>&1 &
fi

# The project is mounted into the pod (see charts/dbt/values.yaml), so editing
# a model needs a re-run, never an image rebuild.
export PROJECT_DIR="$PROJECT_ROOT"

# `skaffold dev` builds, deploys, and holds the portForward entries defined in
# k8s/skaffold.yaml. --cleanup=false keeps the pod running after Ctrl-C.
cd "$PROJECT_ROOT/k8s"
exec skaffold dev --port-forward=user --cleanup=false --tail=false
