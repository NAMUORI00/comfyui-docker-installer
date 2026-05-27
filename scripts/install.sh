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
  --force-public-bind   Deprecated compatibility flag; LAN binding is the default.
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
  local base_image uid gid user_spec bind_host data_dir auth_user
  base_image="$(detect_base_image)"
  uid="$(id -u)"
  gid="$(id -g)"
  user_spec="${COMFYUI_USER_SPEC:-$(normalize_uid_gid)}"
  bind_host="${COMFYUI_BIND_HOST:-0.0.0.0}"
  data_dir="${COMFYUI_DATA_DIR:-./data}"
  auth_user="${CADDY_AUTH_USER:-yskim}"

  cat > "$ENV_FILE" <<EOF
COMFYUI_BASE_IMAGE=${COMFYUI_BASE_IMAGE:-$base_image}
COMFYUI_REF=${COMFYUI_REF:-master}
COMFYUI_IMAGE=${COMFYUI_IMAGE:-comfyui-a6000:local}
COMFYUI_CONTAINER_NAME=${COMFYUI_CONTAINER_NAME:-comfyui-a6000}
COMFYUI_DATA_DIR=${data_dir}
COMFYUI_BIND_HOST=${bind_host}
COMFYUI_HOST_PORT=${COMFYUI_HOST_PORT:-8188}
CADDY_CONTAINER_NAME=${CADDY_CONTAINER_NAME:-comfyui-caddy}
CADDY_AUTH_USER=${auth_user}
COMFYUI_UID=${COMFYUI_UID:-$uid}
COMFYUI_GID=${COMFYUI_GID:-$gid}
COMFYUI_USER_SPEC=${user_spec}
NVIDIA_VISIBLE_DEVICES=${NVIDIA_VISIBLE_DEVICES:-all}
EOF
}

create_data_dirs() {
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  local uid gid dir
  uid="${COMFYUI_UID:-$(id -u)}"
  gid="${COMFYUI_GID:-$(id -g)}"
  mkdir -p \
    "${COMFYUI_DATA_DIR}/models" \
    "${COMFYUI_DATA_DIR}/input" \
    "${COMFYUI_DATA_DIR}/output" \
    "${COMFYUI_DATA_DIR}/custom_nodes" \
    "${COMFYUI_DATA_DIR}/user" \
    "${COMFYUI_DATA_DIR}/caddy"

  if [ "$(id -u)" -eq 0 ]; then
    chown -R "${uid}:${gid}" "${COMFYUI_DATA_DIR}"
  fi

  for dir in \
    "${COMFYUI_DATA_DIR}/models" \
    "${COMFYUI_DATA_DIR}/input" \
    "${COMFYUI_DATA_DIR}/output" \
    "${COMFYUI_DATA_DIR}/custom_nodes" \
    "${COMFYUI_DATA_DIR}/user" \
    "${COMFYUI_DATA_DIR}/caddy"; do
    if [ ! -w "$dir" ]; then
      echo "Data directory is not writable by the current user: $dir" >&2
      echo "Fix ownership or rerun from an account that can write COMFYUI_DATA_DIR." >&2
      return 1
    fi
  done
}

read_auth_password() {
  if [ -n "${CADDY_AUTH_PASSWORD:-}" ]; then
    printf '%s' "$CADDY_AUTH_PASSWORD"
    return 0
  fi

  if [ ! -t 0 ]; then
    echo "Missing CADDY_AUTH_PASSWORD and no interactive terminal is available to read it." >&2
    return 1
  fi

  local password
  read -r -s -p "Caddy Basic Auth password for ${CADDY_AUTH_USER:-yskim}: " password
  printf '\n' >&2
  printf '%s' "$password"
}

write_caddy_config() {
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  local auth_user auth_hash_file caddyfile auth_hash password
  auth_user="${CADDY_AUTH_USER:-yskim}"
  auth_hash_file="${COMFYUI_DATA_DIR}/caddy/auth.hash"
  caddyfile="${COMFYUI_DATA_DIR}/caddy/Caddyfile"

  if [ "${CADDY_AUTH_RESET:-no}" = "yes" ] || [ ! -s "$auth_hash_file" ]; then
    password="$(read_auth_password)"
    if [ -z "$password" ]; then
      echo "Caddy Basic Auth password cannot be empty." >&2
      return 1
    fi
    printf '%s\n' "$password" | docker run --rm -i caddy:2-alpine caddy hash-password --algorithm bcrypt > "$auth_hash_file"
    chmod 600 "$auth_hash_file"
  fi

  auth_hash="$(cat "$auth_hash_file")"
  cat > "$caddyfile" <<EOF
:8188 {
  basic_auth {
    ${auth_user} ${auth_hash}
  }

  reverse_proxy comfyui:8188
}
EOF
}

main() {
  require_command docker
  require_command nvidia-smi
  docker compose version >/dev/null
  require_command nvidia-ctk

  write_env
  create_data_dirs
  write_caddy_config

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
