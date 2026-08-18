#!/usr/bin/env bash
#
# Wait for Postgres, build the project, then serve the dbt docs site so there
# is something to look at on localhost:8080 (the analog of the Spark master UI).
set -euo pipefail

PG_HOST="${DBT_PG_HOST:-postgres}"
PG_PORT="${DBT_PG_PORT:-5432}"
DOCS_PORT="${DBT_DOCS_PORT:-8080}"

echo "==> waiting for Postgres at ${PG_HOST}:${PG_PORT}"
python - <<PY
import os, socket, sys, time
host, port = os.environ.get("DBT_PG_HOST", "postgres"), int(os.environ.get("DBT_PG_PORT", "5432"))
for attempt in range(150):
    try:
        with socket.create_connection((host, port), timeout=2):
            print(f"==> Postgres reachable after {attempt * 2}s")
            sys.exit(0)
    except OSError:
        time.sleep(2)
print("Postgres never became reachable", file=sys.stderr)
sys.exit(1)
PY

if [ "${DBT_BUILD_ON_START:-true}" = "true" ]; then
  echo "==> dbt seed"
  dbt seed
  echo "==> dbt run"
  dbt run
  echo "==> dbt test"
  dbt test
fi

echo "==> generating docs"
dbt docs generate

echo "==> serving docs on :${DOCS_PORT}"
exec dbt docs serve --port "${DOCS_PORT}" --host 0.0.0.0 --no-browser
