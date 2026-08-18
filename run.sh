#!/usr/bin/env bash
# One command to build the whole project locally.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d .venv ]; then
  echo "==> creating virtualenv"
  python3.12 -m venv .venv
  .venv/bin/pip install --upgrade pip
  .venv/bin/pip install dbt-core dbt-duckdb
fi

export DBT_PROFILES_DIR="$PWD"
DBT=.venv/bin/dbt

"$DBT" deps --quiet 2>/dev/null || true
"$DBT" seed
"$DBT" run
"$DBT" test

echo
echo "Done. Query the warehouse with:"
echo "  .venv/bin/python -c \"import duckdb; print(duckdb.connect('warehouse.duckdb').sql('select * from customer_orders'))\""
