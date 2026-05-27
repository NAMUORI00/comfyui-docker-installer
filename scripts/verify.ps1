$ErrorActionPreference = 'Stop'
$ProjectDir = Resolve-Path (Join-Path $PSScriptRoot '..')
$EnvFile = Join-Path $ProjectDir '.env'

if (-not (Test-Path $EnvFile)) {
    throw 'Missing .env. Run scripts/install.ps1 -SkipBuild first or copy .env.example to .env.'
}

Push-Location $ProjectDir
try {
    docker compose config --quiet
    nvidia-smi
    docker compose --env-file $EnvFile run --rm comfyui python -c "import torch; print('torch', torch.__version__); print('cuda_available', torch.cuda.is_available()); raise SystemExit('CUDA is not available inside the container') if not torch.cuda.is_available() else None"
    docker compose --env-file $EnvFile run --rm comfyui pip check
}
finally {
    Pop-Location
}
