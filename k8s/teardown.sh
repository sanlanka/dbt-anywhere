#!/usr/bin/env bash
#
# Remove everything spinup.sh deployed (via Skaffold).
#
#   k8s/teardown.sh              # delete the dbt release
#   k8s/teardown.sh --namespace  # ...and delete the 'data' namespace too
#
# For a local (non-Kubernetes) build, use ./run.sh --clean in the repo root.
#
# Note: this never touches your warehouse. To remove what dbt built there, drop
# the schema it writes into (DBT_SCHEMA in .env, 'analytics' by default).
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

info "Deleting the Skaffold deployment..."
skaffold delete 2>/dev/null || true

info "Deleting the warehouse credentials Secret..."
kubectl delete secret dbt-warehouse -n data --ignore-not-found >/dev/null 2>&1 || true

if [[ "${1:-}" == "--namespace" ]]; then
  info "Deleting namespace 'data'..."
  kubectl delete namespace data --ignore-not-found
fi

info "Teardown complete. Your warehouse was not touched."
