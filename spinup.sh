#!/usr/bin/env bash
#
# One command to bring everything up.
#
#   ./spinup.sh                    # Kubernetes: Postgres + dbt + docs UI
#   ./spinup.sh --local            # same project, no Kubernetes
#   ./spinup.sh --local --duckdb   # ...and no database server at all
#   ./spinup.sh --no-browser       # don't auto-open the docs UI
#
# Either way it ends the same: the project is built, tested, and the dbt docs
# UI is open at http://localhost:8080. Ctrl-C stops it.
# Remove everything with ./teardown.sh
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
error() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

MODE=k8s
TARGET=postgres
OPEN_BROWSER=true
for arg in "$@"; do
  case "$arg" in
    --local)      MODE=local ;;
    --duckdb)     TARGET=duckdb; MODE=local ;;
    --no-browser) OPEN_BROWSER=false ;;
    *) error "Unknown option: $arg (try --local, --duckdb, --no-browser)" ;;
  esac
done

DOCS_URL="http://localhost:8080"

# Poll the docs site in the background and open it once it answers, so the UI
# comes up on its own without blocking the foreground process.
open_docs_when_ready() {
  [[ "$OPEN_BROWSER" == true ]] || return 0
  command -v open >/dev/null 2>&1 || return 0
  (
    for _ in $(seq 1 120); do
      if curl -sf -o /dev/null "$DOCS_URL"; then
        open "$DOCS_URL"
        return 0
      fi
      sleep 2
    done
  ) >/dev/null 2>&1 &
}

# ---------------------------------------------------------------------------
# Local mode — no Kubernetes
# ---------------------------------------------------------------------------
if [[ "$MODE" == local ]]; then
  PG_HOST="${DBT_PG_HOST:-localhost}"
  PG_PORT="${DBT_PG_PORT:-5432}"
  PG_USER="${DBT_PG_USER:-dbt}"
  PG_PASSWORD="${DBT_PG_PASSWORD:-dbt}"
  PG_DATABASE="${DBT_PG_DATABASE:-dbt_local}"

  if [ ! -x .venv/bin/dbt ]; then
    info "Creating the virtualenv (first run only)..."
    command -v python3.12 >/dev/null 2>&1 || \
      error "python3.12 is required (dbt does not support 3.13+ yet). brew install python@3.12"
    python3.12 -m venv .venv
    .venv/bin/pip install --quiet --upgrade pip
    .venv/bin/pip install --quiet dbt-core dbt-postgres dbt-duckdb
  fi

  if [[ "$TARGET" == postgres ]]; then
    can_connect() {
      PGPASSWORD="$PG_PASSWORD" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" \
        -d "$PG_DATABASE" -tAc 'select 1' >/dev/null 2>&1
    }
    if can_connect; then
      info "Using Postgres at $PG_HOST:$PG_PORT/$PG_DATABASE"
    elif command -v pg_isready >/dev/null 2>&1 && pg_isready -h "$PG_HOST" -p "$PG_PORT" -q; then
      info "Creating role '$PG_USER' and database '$PG_DATABASE' on the running Postgres..."
      psql -h "$PG_HOST" -p "$PG_PORT" -d postgres -v ON_ERROR_STOP=1 \
        -c "do \$\$ begin
              if not exists (select 1 from pg_roles where rolname = '$PG_USER') then
                create role $PG_USER login password '$PG_PASSWORD';
              end if;
            end \$\$;" >/dev/null
      psql -h "$PG_HOST" -p "$PG_PORT" -d postgres -tAc \
        "select 1 from pg_database where datname = '$PG_DATABASE'" | grep -q 1 \
        || psql -h "$PG_HOST" -p "$PG_PORT" -d postgres -v ON_ERROR_STOP=1 \
             -c "create database $PG_DATABASE owner $PG_USER" >/dev/null
      can_connect || error "Could not connect as '$PG_USER' after bootstrap."
    elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
      info "No Postgres on $PG_HOST:$PG_PORT — starting one with docker compose..."
      docker compose up -d --wait
    else
      error "No Postgres at $PG_HOST:$PG_PORT and Docker isn't running. Try: ./spinup.sh --duckdb"
    fi
  fi

  export DBT_PROFILES_DIR="$PWD"
  DBT=.venv/bin/dbt

  info "Building the project (seed -> run -> test)..."
  "$DBT" seed --target "$TARGET"
  "$DBT" run  --target "$TARGET"
  "$DBT" test --target "$TARGET"

  "$DBT" docs generate --target "$TARGET" --quiet

  cat <<EOF

Everything is up.
  dbt docs : $DOCS_URL
Press Ctrl-C to stop.

EOF
  open_docs_when_ready
  exec "$DBT" docs serve --port 8080 --no-browser
fi

# ---------------------------------------------------------------------------
# Kubernetes mode
# ---------------------------------------------------------------------------
ensure_brew() {
  command -v brew >/dev/null 2>&1 && return 0
  error "Homebrew is required to auto-install tools. Install it from https://brew.sh then re-run."
}

ensure_tool() {
  local bin="$1" pkg="${2:-$1}"
  if command -v "$bin" >/dev/null 2>&1; then return 0; fi
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

info "Tooling and cluster OK. Context: $(kubectl config current-context)"

cat <<EOF

Building the dbt image and deploying via Skaffold...
The pod waits for Postgres, runs seed -> run -> test, then serves the docs.
Once ready (the browser opens on its own):
  dbt docs : $DOCS_URL
  Postgres : localhost:15432  (user dbt / password dbt / db dbt_local)
             15432, not 5432, so a Postgres already on your Mac keeps its port.
Port-forwarding is handled by Skaffold. Press Ctrl-C to stop it.

EOF

# Mount this repo into the dbt pod so model edits are picked up without a rebuild.
export PROJECT_DIR="$PWD"

open_docs_when_ready

# `skaffold dev` builds, deploys, and holds the portForward entries defined in
# skaffold.yaml. --cleanup=false keeps the cluster running after Ctrl-C.
exec skaffold dev --port-forward=user --cleanup=false --tail=false
