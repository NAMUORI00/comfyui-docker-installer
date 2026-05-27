param(
    [switch]$ResetPython
)

$ErrorActionPreference = 'Stop'
$ProjectDir = Resolve-Path (Join-Path $PSScriptRoot '..')
$EnvFile = Join-Path $ProjectDir '.env'

if (-not (Test-Path $EnvFile)) {
    throw 'Missing .env. Run scripts/install.ps1 -SkipBuild first.'
}

$resetValue = if ($ResetPython) { '1' } else { '0' }
$installScript = @'
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
'@

Write-Host 'Installing requirements for trusted custom nodes only.'

Push-Location $ProjectDir
try {
    docker compose --env-file $EnvFile run --rm --no-deps -e RESET_PYTHON=$resetValue comfyui sh -lc $installScript
}
finally {
    Pop-Location
}
