#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${PROJECT_DIR}/.env"
APPLY_RUNTIME_FIX=0
START_AFTER_BUILD=0
FORCE_PUBLIC_BIND=0
SKIP_BUILD=0

usage() {
  cat <<'USAGE'
Usage: scripts/install.sh [options]

Options:
  --apply-runtime-fix   Run sudo nvidia-ctk runtime configure --runtime=docker and restart Docker if needed.
  --start               Start ComfyUI after a successful build and verification.
  --skip-build          Generate configuration and directories without building the image.
  --force-public-bind   Allow COMFYUI_BIND_HOST values other than 127.0.0.1. Not recommended.
  -h, --help            Show this help.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply-runtime-fix) APPLY_RUNTIME_FIX=1 ;;
    --start) START_AFTER_BUILD=1 ;;
    --skip-build) SKIP_BUILD=1 ;;
    --force-public-bind) FORCE_PUBLIC_BIND=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    return 1
  fi
}

detect_base_image() {
  local driver cuda_line cuda_major cuda_minor
  driver="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits 2>/dev/null | head -n1 || true)"
  cuda_line="$(nvidia-smi 2>/dev/null | sed -n 's/.*CUDA Version: \([0-9][0-9.]*\).*/\1/p' | head -n1 || true)"
  cuda_major="${cuda_line%%.*}"
  cuda_minor="${cuda_line#*.}"

  case "$driver" in
    535.*)
      echo "pytorch/pytorch:2.4.1-cuda12.1-cudnn9-runtime"
      return 0
      ;;
  esac

  if [ "${cuda_major:-0}" -ge 13 ]; then
    echo "CUDA ${cuda_line} hosts should set COMFYUI_BASE_IMAGE explicitly after compatibility validation." >&2
    return 1
  elif [ "${cuda_major:-0}" -eq 12 ] && [ "${cuda_minor:-0}" -ge 1 ]; then
    echo "pytorch/pytorch:2.4.1-cuda12.1-cudnn9-runtime"
  else
    echo "Unsupported or unknown NVIDIA CUDA runtime from nvidia-smi: ${cuda_line:-unknown}" >&2
    return 1
  fi
}

docker_has_nvidia_runtime() {
  docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"'
}

normalize_uid_gid() {
  local uid gid
  uid="${COMFYUI_UID:-$(id -u)}"
  gid="${COMFYUI_GID:-$(id -g)}"
  printf '%s:%s\n' "$uid" "$gid"
}

ensure_nvidia_runtime() {
  if docker_has_nvidia_runtime; then
    return 0
  fi

  if [ "$APPLY_RUNTIME_FIX" -ne 1 ]; then
    cat >&2 <<'MSG'
Docker daemon NVIDIA runtime is not configured.
Run this installer again with --apply-runtime-fix, or run manually:
  sudo nvidia-ctk runtime configure --runtime=docker
  sudo systemctl restart docker
MSG
    return 1
  fi

  echo "sudo authentication is required to configure Docker's NVIDIA runtime and restart Docker."
  sudo -v
  sudo nvidia-ctk runtime configure --runtime=docker
  sudo systemctl restart docker
  docker_has_nvidia_runtime
}

write_env() {
  local base_image uid gid user_spec bind_host data_dir
  base_image="$(detect_base_image)"
  uid="$(id -u)"
  gid="$(id -g)"
  user_spec="${COMFYUI_USER_SPEC:-$(normalize_uid_gid)}"
  bind_host="${COMFYUI_BIND_HOST:-127.0.0.1}"
  data_dir="${COMFYUI_DATA_DIR:-./data}"

  if [ "$bind_host" != "127.0.0.1" ] && [ "$FORCE_PUBLIC_BIND" -ne 1 ]; then
    echo "Refusing public bind '${bind_host}'. Use --force-public-bind only with an approved auth/network plan." >&2
    return 1
  fi

  cat > "$ENV_FILE" <<EOF
COMFYUI_BASE_IMAGE=${COMFYUI_BASE_IMAGE:-$base_image}
COMFYUI_IMAGE=${COMFYUI_IMAGE:-comfyui-a6000:local}
COMFYUI_CONTAINER_NAME=${COMFYUI_CONTAINER_NAME:-comfyui-a6000}
COMFYUI_DATA_DIR=${data_dir}
COMFYUI_HOST_PORT=${COMFYUI_HOST_PORT:-8188}
COMFYUI_UID=${COMFYUI_UID:-$uid}
COMFYUI_GID=${COMFYUI_GID:-$gid}
COMFYUI_USER_SPEC=${user_spec}
NVIDIA_VISIBLE_DEVICES=${NVIDIA_VISIBLE_DEVICES:-all}
EOF
}

create_data_dirs() {
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  mkdir -p \
    "${COMFYUI_DATA_DIR}/models" \
    "${COMFYUI_DATA_DIR}/input" \
    "${COMFYUI_DATA_DIR}/output" \
    "${COMFYUI_DATA_DIR}/custom_nodes" \
    "${COMFYUI_DATA_DIR}/user"
}

main() {
  require_command docker
  require_command nvidia-smi
  docker compose version >/dev/null
  require_command nvidia-ctk

  write_env
  create_data_dirs

  if [ "$SKIP_BUILD" -eq 1 ]; then
    echo "Configuration written to ${ENV_FILE}; build skipped."
    return 0
  fi

  ensure_nvidia_runtime
  docker compose --env-file "$ENV_FILE" -f "${PROJECT_DIR}/compose.yaml" build --pull
  "${PROJECT_DIR}/scripts/verify.sh"

  if [ "$START_AFTER_BUILD" -eq 1 ]; then
    docker compose --env-file "$ENV_FILE" -f "${PROJECT_DIR}/compose.yaml" up -d
  fi
}

main "$@"
