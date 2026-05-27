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
if ss -ltnp 2>/dev/null | grep ':8188' | grep -q '0.0.0.0'; then
  echo "ComfyUI is publicly bound to 0.0.0.0; this package expects localhost-only exposure." >&2
  exit 1
fi

echo "verification complete"
