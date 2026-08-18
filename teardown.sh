#!/usr/bin/env bash
#
# Remove what run.sh created.
#
#   ./teardown.sh          # drop the built tables/views + local build artifacts
#   ./teardown.sh --all    # ...and the database, the venv, and the Docker volume
#   ./teardown.sh --all --yes   # no confirmation prompt
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*"; }

ALL=false
ASSUME_YES=false
for arg in "$@"; do
  case "$arg" in
    --all) ALL=true ;;
    --yes|-y) ASSUME_YES=true ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

PG_HOST="${DBT_PG_HOST:-localhost}"
PG_PORT="${DBT_PG_PORT:-5432}"
PG_USER="${DBT_PG_USER:-dbt}"
PG_PASSWORD="${DBT_PG_PASSWORD:-dbt}"
PG_DATABASE="${DBT_PG_DATABASE:-dbt_local}"
PG_SCHEMA="${DBT_PG_SCHEMA:-analytics}"

pg_reachable() {
  PGPASSWORD="$PG_PASSWORD" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" \
    -d "$PG_DATABASE" -tAc 'select 1' >/dev/null 2>&1
}

# --- built objects ----------------------------------------------------------
if pg_reachable; then
  info "Dropping schema '$PG_SCHEMA' from $PG_DATABASE..."
  PGPASSWORD="$PG_PASSWORD" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" \
    -d "$PG_DATABASE" -q -c "drop schema if exists $PG_SCHEMA cascade;"
else
  info "No reachable Postgres at $PG_HOST:$PG_PORT/$PG_DATABASE — skipping."
fi

info "Removing build artifacts (target/, logs/, warehouse.duckdb)..."
rm -rf target logs warehouse.duckdb warehouse.duckdb.wal

# --- everything else --------------------------------------------------------
if [[ "$ALL" == true ]]; then
  if [[ "$ASSUME_YES" != true ]]; then
    warn "This will DROP DATABASE $PG_DATABASE and delete .venv/."
    read -r -p "    Type the database name to confirm: " reply
    if [[ "$reply" != "$PG_DATABASE" ]]; then
      echo "    Not confirmed — stopping here. Built objects were still removed."
      exit 0
    fi
  fi

  if command -v pg_isready >/dev/null 2>&1 && pg_isready -h "$PG_HOST" -p "$PG_PORT" -q; then
    info "Dropping database '$PG_DATABASE'..."
    psql -h "$PG_HOST" -p "$PG_PORT" -d postgres -q \
      -c "drop database if exists $PG_DATABASE;" \
      || warn "Could not drop '$PG_DATABASE' (need superuser, or it's in use)."
  fi

  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    info "Removing the Docker Postgres and its volume..."
    docker compose down -v 2>/dev/null || true
  fi

  info "Removing the virtualenv..."
  rm -rf .venv
fi

info "Teardown complete."
