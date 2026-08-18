#!/usr/bin/env bash
# Build the whole project locally: bootstrap the warehouse, then seed/run/test.
#
#   ./run.sh                  # Postgres (default)
#   ./run.sh --target duckdb  # no server at all, warehouse is one file
set -euo pipefail
cd "$(dirname "$0")"

TARGET="${DBT_TARGET:-postgres}"
if [ "${1:-}" = "--target" ] && [ -n "${2:-}" ]; then TARGET="$2"; fi

PG_HOST="${DBT_PG_HOST:-localhost}"
PG_PORT="${DBT_PG_PORT:-5432}"
PG_USER="${DBT_PG_USER:-dbt}"
PG_PASSWORD="${DBT_PG_PASSWORD:-dbt}"
PG_DATABASE="${DBT_PG_DATABASE:-dbt_local}"

log() { printf '==> %s\n' "$1"; }

# --- virtualenv -------------------------------------------------------------
if [ ! -x .venv/bin/dbt ]; then
  log "creating virtualenv"
  python3.12 -m venv .venv
  .venv/bin/pip install --quiet --upgrade pip
  .venv/bin/pip install --quiet dbt-core dbt-postgres dbt-duckdb
fi

# --- warehouse --------------------------------------------------------------
can_connect() {
  PGPASSWORD="$PG_PASSWORD" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" \
    -d "$PG_DATABASE" -tAc 'select 1' >/dev/null 2>&1
}

server_listening() {
  command -v pg_isready >/dev/null 2>&1 && pg_isready -h "$PG_HOST" -p "$PG_PORT" -q
}

bootstrap_native() {
  # A Postgres is already running but lacks our role/database. Create them as
  # the current OS user (the default superuser on a Homebrew install).
  log "creating role '$PG_USER' and database '$PG_DATABASE' on the running Postgres"
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
}

if [ "$TARGET" = "postgres" ]; then
  if can_connect; then
    log "using Postgres at $PG_HOST:$PG_PORT/$PG_DATABASE"
  elif server_listening; then
    bootstrap_native
    can_connect || { echo "Could not connect as '$PG_USER' after bootstrap." >&2; exit 1; }
  elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    log "no Postgres on $PG_HOST:$PG_PORT — starting one with docker compose"
    docker compose up -d --wait
  else
    cat >&2 <<MSG
No Postgres reachable at $PG_HOST:$PG_PORT, and Docker isn't running.

Pick one:
  * start Docker Desktop, then re-run ./run.sh   (uses docker-compose.yml)
  * brew install postgresql@16 && brew services start postgresql@16
  * skip Postgres entirely:  ./run.sh --target duckdb
MSG
    exit 1
  fi
fi

# --- build ------------------------------------------------------------------
export DBT_PROFILES_DIR="$PWD"
DBT=.venv/bin/dbt

"$DBT" seed --target "$TARGET"
"$DBT" run  --target "$TARGET"
"$DBT" test --target "$TARGET"

echo
if [ "$TARGET" = "postgres" ]; then
  echo "Done. Inspect it with:"
  echo "  PGPASSWORD=$PG_PASSWORD psql -h $PG_HOST -p $PG_PORT -U $PG_USER -d $PG_DATABASE -c 'table analytics.customer_orders'"
else
  echo "Done. Inspect it with:"
  echo "  .venv/bin/python -c \"import duckdb; print(duckdb.connect('warehouse.duckdb').sql('select * from analytics.customer_orders'))\""
fi
