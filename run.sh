#!/usr/bin/env bash
#
# Build the project and open the docs UI. This is the main entry point.
#
#   ./run.sh              # use .env (or the DuckDB sandbox if there is no .env)
#   ./run.sh --duckdb     # force the sandbox: no warehouse, no server
#   ./run.sh --no-browser # don't open a browser tab
#   ./run.sh --clean      # remove the venv and build output, then exit
#
# To run the same project on Kubernetes instead: k8s/spinup.sh
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
error() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

FORCE_DUCKDB=false
OPEN_BROWSER=true
for arg in "$@"; do
  case "$arg" in
    --duckdb)     FORCE_DUCKDB=true ;;
    --no-browser) OPEN_BROWSER=false ;;
    --clean)
      info "Removing .venv/, target/, logs/, warehouse.duckdb..."
      rm -rf .venv target logs warehouse.duckdb warehouse.duckdb.wal
      info "Clean. Your warehouse was not touched."
      exit 0 ;;
    *) error "Unknown option: $arg (try --duckdb, --no-browser, --clean)" ;;
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
