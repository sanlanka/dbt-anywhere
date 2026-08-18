#!/usr/bin/env bash
#
# Verify the warehouse connection, build the project, then serve the dbt docs
# site so there is something to look at on localhost:8080.
set -euo pipefail

DOCS_PORT="${DBT_DOCS_PORT:-8080}"
TARGET="${DBT_TARGET:-postgres}"

echo "==> checking the '${TARGET}' connection"
attempt=0
until dbt debug --connection --target "$TARGET" >/tmp/debug.log 2>&1; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 20 ]; then
    echo "Could not connect to the warehouse after $attempt attempts:" >&2
    tail -25 /tmp/debug.log >&2
    cat >&2 <<'MSG'

Check that:
  * .env has the right credentials, and you re-ran ./spinup.sh after editing it
  * the warehouse allows connections from this network
  * DBT_TARGET names a target that exists in profiles.yml
MSG
    exit 1
  fi
  echo "    not reachable yet (attempt ${attempt}/20), retrying in 5s..."
  sleep 5
done
echo "==> connection OK"

if [ "${DBT_BUILD_ON_START:-true}" = "true" ]; then
  echo "==> dbt seed"
  dbt seed --target "$TARGET"
  echo "==> dbt run"
  dbt run --target "$TARGET"
  echo "==> dbt test"
  dbt test --target "$TARGET"
fi

echo "==> generating docs"
dbt docs generate --target "$TARGET"

echo "==> serving docs on :${DOCS_PORT}"
exec dbt docs serve --port "${DOCS_PORT}" --host 0.0.0.0 --no-browser
