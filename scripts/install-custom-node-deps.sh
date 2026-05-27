#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${PROJECT_DIR}/.env"
RESET_PYTHON=0

usage() {
  cat <<'USAGE'
Usage: scripts/install-custom-node-deps.sh [options]

Options:
  --reset-python   Remove the persistent Python user base before installing requirements.
  -h, --help       Show this help.

Only run this for trusted custom nodes. Python package installation can execute
code from the downloaded node or its dependencies.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --reset-python) RESET_PYTHON=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing .env. Run scripts/install.sh --skip-build first." >&2
  exit 1
fi

cd "$PROJECT_DIR"

echo "Installing requirements for trusted custom nodes only."

RESET_PYTHON="$RESET_PYTHON" docker compose --env-file "$ENV_FILE" run --rm --no-deps comfyui sh -lc '
set -eu
echo "PYTHONUSERBASE=${PYTHONUSERBASE:-}"
if [ "${PYTHONUSERBASE:-}" != "/opt/comfyui-python" ]; then
  echo "PYTHONUSERBASE must be /opt/comfyui-python" >&2
  exit 1
fi

if [ "${RESET_PYTHON:-0}" = "1" ]; then
  echo "Resetting persistent Python user base at /opt/comfyui-python"
  find /opt/comfyui-python -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi

found=0
for requirements in /opt/ComfyUI/custom_nodes/*/requirements.txt; do
  [ -f "$requirements" ] || continue
  found=1
  echo "Installing custom node requirements: $requirements"
  python -m pip install --user -r "$requirements"
done

if [ "$found" -eq 0 ]; then
  echo "No custom node requirements.txt files found."
fi

python - <<PY
import os
import site
print("USER_SITE", site.USER_SITE)
if not site.USER_SITE.startswith("/opt/comfyui-python/"):
    raise SystemExit(f"Unexpected USER_SITE: {site.USER_SITE}")
PY
'
