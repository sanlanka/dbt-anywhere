#!/usr/bin/env bash
#
# One command to bring everything up. dbt connects to YOUR warehouse — nothing
# here runs a database for you.
#
#   cp .env.example .env      # fill in your warehouse once (repo root)
#   k8s/spinup.sh             # build, deploy, run, serve the docs UI
#   k8s/spinup.sh --no-browser
#
# The project is built and tested inside the cluster and the dbt docs UI is
# served at http://localhost:8080. Ctrl-C stops the port-forward.
# Remove everything with k8s/teardown.sh
#
# To run the same project without Kubernetes, use ./run.sh in the repo root.
#
set -euo pipefail
K8S_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$K8S_DIR/.." && pwd)"
cd "$K8S_DIR"

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
error() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

OPEN_BROWSER=true
for arg in "$@"; do
  case "$arg" in
    --no-browser) OPEN_BROWSER=false ;;
    *) error "Unknown option: $arg (only --no-browser is supported; for a local run use ./run.sh)" ;;
  esac
done

DOCS_URL="http://localhost:8080"
NAMESPACE=data
SECRET_NAME=dbt-warehouse

# --- Warehouse settings -----------------------------------------------------
# .env lives in the repo root and holds your connection details. It becomes a
# Kubernetes Secret so the pod can read it; it is never baked into the image.
ENV_FILE="$PROJECT_ROOT/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  cat >&2 <<MSG
No .env found at $ENV_FILE, so there is no warehouse to connect to.

  cp .env.example .env     # then fill in your warehouse and re-run

Or try the models with no warehouse at all, without Kubernetes:

  ./run.sh --duckdb

MSG
  exit 1
fi

# Poll the docs site in the background and open it once it answers, so the UI
# comes up on its own without blocking the foreground process.
open_docs_when_ready() {
  [[ "$OPEN_BROWSER" == true ]] || return 0
  command -v open >/dev/null 2>&1 || return 0
  (
    for _ in $(seq 1 180); do
      if curl -sf -o /dev/null "$DOCS_URL"; then open "$DOCS_URL"; return 0; fi
      sleep 2
    done
  ) >/dev/null 2>&1 &
}

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

# Hand the warehouse credentials to the pod as a Secret built from .env, so they
# stay out of the chart, out of `helm get values`, and out of git.
info "Publishing warehouse credentials to Secret '$SECRET_NAME' in '$NAMESPACE'..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl create secret generic "$SECRET_NAME" --namespace "$NAMESPACE" \
  --from-env-file="$ENV_FILE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

cat <<EOF

Building the dbt image and deploying via Skaffold...
The pod checks the warehouse connection, runs seed -> run -> test, then serves
the docs. Once ready (the browser opens on its own):
  dbt docs : $DOCS_URL
Press Ctrl-C to stop the port-forward.

EOF

# Mount the project (repo root) into the dbt pod so model edits are picked up
# without an image rebuild.
export PROJECT_DIR="$PROJECT_ROOT"

open_docs_when_ready

# `skaffold dev` builds, deploys, and holds the portForward entries defined in
# skaffold.yaml. --cleanup=false keeps the cluster running after Ctrl-C.
exec skaffold dev --port-forward=user --cleanup=false --tail=false
