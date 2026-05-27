#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${PROJECT_DIR}/.env"
REMOVE_IMAGE=0
REMOVE_DATA=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --remove-image) REMOVE_IMAGE=1 ;;
    --remove-data) REMOVE_DATA=1 ;;
    -h|--help)
      echo "Usage: scripts/uninstall.sh [--remove-image] [--remove-data]"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

cd "$PROJECT_DIR"
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  docker compose --env-file "$ENV_FILE" down
else
  docker compose down
fi

if [ "$REMOVE_IMAGE" -eq 1 ]; then
  docker image rm "${COMFYUI_IMAGE:-comfyui-a6000:local}" || true
fi

if [ "$REMOVE_DATA" -eq 1 ]; then
  if [ "${CONFIRM_REMOVE_DATA:-}" != "yes" ]; then
    echo "Set CONFIRM_REMOVE_DATA=yes to delete persistent data." >&2
    exit 1
  fi
  rm -rf "${COMFYUI_DATA_DIR:?}"
fi
