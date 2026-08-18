#!/usr/bin/env bash
#
# Remove everything spinup.sh deployed (via Skaffold).
#
#   ./teardown.sh              # delete the dbt + Postgres release
#   ./teardown.sh --namespace  # ...and delete the 'data' namespace too
#   ./teardown.sh --local      # instead: clean up a local (non-k8s) run.sh build
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

# --- Local (non-Kubernetes) build ------------------------------------------
if [[ "${1:-}" == "--local" ]]; then
  PG_HOST="${DBT_PG_HOST:-localhost}"
  PG_PORT="${DBT_PG_PORT:-5432}"
  PG_USER="${DBT_PG_USER:-dbt}"
  PG_PASSWORD="${DBT_PG_PASSWORD:-dbt}"
  PG_DATABASE="${DBT_PG_DATABASE:-dbt_local}"
  PG_SCHEMA="${DBT_PG_SCHEMA:-analytics}"

  if PGPASSWORD="$PG_PASSWORD" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" \
       -d "$PG_DATABASE" -tAc 'select 1' >/dev/null 2>&1; then
    info "Dropping schema '$PG_SCHEMA' from $PG_DATABASE..."
    PGPASSWORD="$PG_PASSWORD" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" \
      -d "$PG_DATABASE" -q -c "drop schema if exists $PG_SCHEMA cascade;"
  else
    info "No reachable Postgres at $PG_HOST:$PG_PORT/$PG_DATABASE — skipping."
  fi

  info "Removing local build artifacts (target/, logs/, warehouse.duckdb, .venv/)..."
  rm -rf target logs warehouse.duckdb warehouse.duckdb.wal .venv

  info "Teardown complete."
  exit 0
fi

# --- Kubernetes ------------------------------------------------------------
info "Deleting the Skaffold deployment..."
skaffold delete 2>/dev/null || true

if [[ "${1:-}" == "--namespace" ]]; then
  info "Deleting namespace 'data'..."
  kubectl delete namespace data --ignore-not-found
fi

info "Teardown complete."
