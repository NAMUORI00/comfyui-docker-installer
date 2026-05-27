#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${PROJECT_DIR}/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing .env. Run scripts/install.sh --skip-build first or copy .env.example to .env." >&2
  exit 1
fi

# shellcheck disable=SC1090
. "$ENV_FILE"

cd "$PROJECT_DIR"
PYTHON_BIN="$(command -v python3 || command -v python || true)"

echo "== compose config =="
docker compose config --quiet

echo "== host gpu =="
nvidia-smi

echo "== container torch cuda =="
docker compose --env-file "$ENV_FILE" run --rm comfyui python - <<'PY'
import torch
print("torch", torch.__version__)
print("torch_cuda", torch.version.cuda)
print("cuda_available", torch.cuda.is_available())
print("device_count", torch.cuda.device_count())
if torch.cuda.is_available():
    print("device_0", torch.cuda.get_device_name(0))
else:
    raise SystemExit("CUDA is not available inside the container")
PY

echo "== package consistency =="
docker compose --env-file "$ENV_FILE" run --rm comfyui pip check

echo "== ownership check =="
docker compose --env-file "$ENV_FILE" run --rm comfyui sh -lc 'touch /opt/ComfyUI/output/.ownership-check && stat -c "%u:%g %n" /opt/ComfyUI/output/.ownership-check && rm /opt/ComfyUI/output/.ownership-check'

echo "== port exposure check =="
published_json="$(docker compose --env-file "$ENV_FILE" ps --format json 2>/dev/null || true)"
if [ -n "$published_json" ]; then
  if [ -z "$PYTHON_BIN" ]; then
    echo "python3 or python is required to validate Docker Compose published ports." >&2
    exit 1
  fi
  COMFYUI_BIND_HOST="${COMFYUI_BIND_HOST:-0.0.0.0}" COMFYUI_HOST_PORT="${COMFYUI_HOST_PORT:-8188}" PUBLISHED_JSON="$published_json" "$PYTHON_BIN" - <<'PY'
import json
import os

raw = os.environ["PUBLISHED_JSON"].strip()
if not raw:
    raise SystemExit(0)

try:
    services = json.loads(raw)
except json.JSONDecodeError:
    services = [json.loads(line) for line in raw.splitlines() if line.strip()]

if isinstance(services, dict):
    services = [services]

expected_port = str(os.environ["COMFYUI_HOST_PORT"])
expected_host = os.environ["COMFYUI_BIND_HOST"]
bad_publishers = []

for service in services:
    for publisher in service.get("Publishers") or []:
        published_port = str(publisher.get("PublishedPort", ""))
        target_port = str(publisher.get("TargetPort", ""))
        if published_port == expected_port or target_port == "8188":
            host = publisher.get("URL") or ""
            if expected_host == "0.0.0.0":
                host_matches = host in {"", "0.0.0.0", "::"}
            elif expected_host == "127.0.0.1":
                host_matches = host in {"127.0.0.1", "localhost"}
            else:
                host_matches = host == expected_host
            if not host_matches:
                bad_publishers.append(f"{host}:{published_port}->{target_port}")

if bad_publishers:
    raise SystemExit(
        f"ComfyUI published endpoint does not match COMFYUI_BIND_HOST={expected_host}: "
        + ", ".join(bad_publishers)
    )
PY
fi

echo "verification complete"
