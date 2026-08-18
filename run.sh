#!/usr/bin/env bash
#
# Build the project and open the docs UI. This is the main entry point.
#
#   ./run.sh              # use .env (or the DuckDB sandbox if there is no .env)
#   ./run.sh --duckdb     # force the sandbox: no warehouse, no server
#   ./run.sh --no-browser # don't open a browser tab
#   ./run.sh --clean      # remove the venv and build output, then exit
#   ./run.sh --yes        # don't prompt before creating a missing database
#
# To run the same project on Kubernetes instead: k8s/spinup.sh
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
error() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

FORCE_DUCKDB=false
OPEN_BROWSER=true
ASSUME_YES=false
for arg in "$@"; do
  case "$arg" in
    --duckdb)     FORCE_DUCKDB=true ;;
    --no-browser) OPEN_BROWSER=false ;;
    --yes|-y)     ASSUME_YES=true ;;
    --clean)
      info "Removing .venv/, target/, logs/, warehouse.duckdb..."
      rm -rf .venv target logs warehouse.duckdb warehouse.duckdb.wal
      info "Clean. Your warehouse was not touched."
      exit 0 ;;
    *) error "Unknown option: $arg (try --duckdb, --no-browser, --clean, --yes)" ;;
  esac
done

DOCS_URL="http://localhost:8080"

# .env holds your warehouse connection and is gitignored. Without one, every
# value in profiles.yml falls back to its default, which is the DuckDB sandbox.
if [[ "$FORCE_DUCKDB" == true ]]; then
  export DBT_TARGET=duckdb
  info "Sandbox mode: DuckDB, no warehouse needed."
elif [[ -f .env ]]; then
  set -a; . ./.env; set +a
  info "Loaded warehouse settings from .env (target: ${DBT_TARGET:-duckdb})"
else
  info "No .env found — using the DuckDB sandbox. Copy .env.example to connect a warehouse."
fi

TARGET="${DBT_TARGET:-duckdb}"

if [ ! -x .venv/bin/dbt ]; then
  info "Creating the virtualenv (first run only)..."
  command -v python3.12 >/dev/null 2>&1 || \
    error "python3.12 is required (dbt does not support 3.13+ yet). brew install python@3.12"
  python3.12 -m venv .venv
  .venv/bin/pip install --quiet --upgrade pip
  .venv/bin/pip install --quiet dbt-core dbt-duckdb dbt-postgres
fi

export DBT_PROFILES_DIR="$PWD"
DBT=.venv/bin/dbt

# dbt creates schemas, but never databases. On a server you own (Postgres or
# Redshift) offer to create a missing one, so a first run is a single command.
# Cloud warehouses are left alone — creating databases there is rarely yours
# to do, and usually not permitted.
ensure_database() {
  case "$TARGET" in postgres|redshift) ;; *) return 0 ;; esac

  local host port user password dbname status
  if [[ "$TARGET" == postgres ]]; then
    host="${DBT_PG_HOST:-localhost}"; port="${DBT_PG_PORT:-5432}"
    user="${DBT_PG_USER:-dbt}"; password="${DBT_PG_PASSWORD:-}"
    dbname="${DBT_PG_DATABASE:-analytics}"
  else
    host="${DBT_REDSHIFT_HOST:-localhost}"; port="${DBT_REDSHIFT_PORT:-5439}"
    user="${DBT_REDSHIFT_USER:-dbt}"; password="${DBT_REDSHIFT_PASSWORD:-}"
    dbname="${DBT_REDSHIFT_DATABASE:-analytics}"
  fi

  # 0 = database is there, 3 = server reachable but database missing,
  # anything else = bad host or credentials, which dbt will report properly.
  # `|| status=$?` matters: a bare non-zero exit would trip `set -e` and kill
  # the script before we ever get to the prompt.
  status=0
  PGHOST="$host" PGPORT="$port" PGUSER="$user" PGPASSWORD="$password" PGDB="$dbname" \
    .venv/bin/python .dbt-ensure-db.py check || status=$?
  [[ $status -eq 3 ]] || return 0

  if [[ "$ASSUME_YES" != true ]]; then
    if [[ ! -t 0 ]]; then
      error "Database '$dbname' does not exist on $host:$port. Create it, or re-run with --yes."
    fi
    printf '\033[1;33m==>\033[0m Database %s does not exist on %s:%s. Create it? [y/N] ' \
      "'$dbname'" "$host" "$port"
    read -r reply
    [[ "$reply" =~ ^[Yy] ]] || error "Not created. Create the database, then re-run."
  fi

  info "Creating database '$dbname'..."
  PGHOST="$host" PGPORT="$port" PGUSER="$user" PGPASSWORD="$password" PGDB="$dbname" \
    .venv/bin/python .dbt-ensure-db.py create \
    || error "Could not create '$dbname' — you may lack CREATEDB permission."
}

ensure_database

info "Checking the '$TARGET' connection..."
"$DBT" debug --connection --target "$TARGET" >/tmp/dbt-debug.log 2>&1 || {
  tail -20 /tmp/dbt-debug.log >&2
  error "Could not connect to '$TARGET'. Check .env, and that the adapter is installed:
    .venv/bin/pip install dbt-${TARGET}"
}

info "Building (seed -> run -> test)..."
"$DBT" seed --target "$TARGET"
"$DBT" run  --target "$TARGET"
"$DBT" test --target "$TARGET"
"$DBT" docs generate --target "$TARGET" --quiet

# Poll the docs site and open it once it answers, rather than guessing a delay.
if [[ "$OPEN_BROWSER" == true ]] && command -v open >/dev/null 2>&1; then
  ( for _ in $(seq 1 60); do
      curl -sf -o /dev/null "$DOCS_URL" && { open "$DOCS_URL"; break; }
      sleep 1
    done ) >/dev/null 2>&1 &
fi

cat <<EOF

Everything is up.
  dbt docs : $DOCS_URL
Press Ctrl-C to stop.

EOF
exec "$DBT" docs serve --port 8080 --no-browser
