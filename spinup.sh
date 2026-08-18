#!/usr/bin/env bash
#
# One-stop-shop: install missing tooling, build the dbt image, deploy Postgres +
# dbt via Skaffold, run the project, and hold the port-forwards.
#
# Just run:  ./spinup.sh
# Stop with: Ctrl-C   (resources are left running; use ./teardown.sh to remove)
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
error() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# --- Install prerequisites (assume nothing) -------------------------------
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

# --- Verify the environment -----------------------------------------------
docker info >/dev/null 2>&1 || error "Docker daemon not reachable. Start Docker Desktop and try again."
kubectl cluster-info >/dev/null 2>&1 || \
  error "No reachable Kubernetes cluster. Enable Kubernetes in Docker Desktop (Settings > Kubernetes), or start minikube."

info "Tooling and cluster OK. Context: $(kubectl config current-context)"

# --- Spin everything up ----------------------------------------------------
cat <<EOF

Building the dbt image and deploying via Skaffold...
The pod waits for Postgres, then runs seed -> run -> test, then serves the docs.
Once ready:
  dbt docs : http://localhost:8080
  Postgres : localhost:15432  (user dbt / password dbt / db dbt_local)
             15432, not 5432, so a Postgres already on your Mac keeps its port.
Port-forwarding is handled by Skaffold. Press Ctrl-C to stop it.

EOF

# Mount this repo into the dbt pod so model edits are picked up without a rebuild.
export PROJECT_DIR="$PWD"

# `skaffold dev` builds, deploys, and holds the portForward entries defined in
# skaffold.yaml. --cleanup=false keeps the cluster running after Ctrl-C.
exec skaffold dev --port-forward=user --cleanup=false --tail=false
