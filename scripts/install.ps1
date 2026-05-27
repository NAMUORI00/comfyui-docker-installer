param(
    [switch]$SkipBuild,
    [switch]$Start,
    [switch]$ForcePublicBind,
    [string]$DataDir = './data'
)

$ErrorActionPreference = 'Stop'
$ProjectDir = Resolve-Path (Join-Path $PSScriptRoot '..')
$EnvFile = Join-Path $ProjectDir '.env'

function Require-Command($Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Missing required command: $Name"
    }
}

function Detect-BaseImage {
    $smi = (& nvidia-smi 2>$null) -join "`n"
    if ($smi -match 'Driver Version:\s*535\.') {
        return 'pytorch/pytorch:2.4.1-cuda12.1-cudnn9-runtime'
    }
    if ($smi -match 'CUDA Version:\s*12\.') {
        return 'pytorch/pytorch:2.4.1-cuda12.1-cudnn9-runtime'
    }
    throw 'Unsupported or unknown CUDA version. Set COMFYUI_BASE_IMAGE explicitly after compatibility validation.'
}

Require-Command docker
Require-Command nvidia-smi
docker compose version | Out-Null

$bindHost = if ($env:COMFYUI_BIND_HOST) { $env:COMFYUI_BIND_HOST } else { '0.0.0.0' }

$baseImage = if ($env:COMFYUI_BASE_IMAGE) { $env:COMFYUI_BASE_IMAGE } else { Detect-BaseImage }
$dataPath = if ($env:COMFYUI_DATA_DIR) { $env:COMFYUI_DATA_DIR } else { $DataDir }
# Default emitted value: COMFYUI_DATA_DIR=./data

@"
COMFYUI_BASE_IMAGE=$baseImage
COMFYUI_REF=$(if ($env:COMFYUI_REF) { $env:COMFYUI_REF } else { 'master' })
COMFYUI_IMAGE=$(if ($env:COMFYUI_IMAGE) { $env:COMFYUI_IMAGE } else { 'comfyui-a6000:local' })
COMFYUI_CONTAINER_NAME=$(if ($env:COMFYUI_CONTAINER_NAME) { $env:COMFYUI_CONTAINER_NAME } else { 'comfyui-a6000' })
COMFYUI_DATA_DIR=$dataPath
COMFYUI_BIND_HOST=$bindHost
COMFYUI_HOST_PORT=$(if ($env:COMFYUI_HOST_PORT) { $env:COMFYUI_HOST_PORT } else { '8188' })
COMFYUI_UID=
COMFYUI_GID=
COMFYUI_USER_SPEC=
NVIDIA_VISIBLE_DEVICES=$(if ($env:NVIDIA_VISIBLE_DEVICES) { $env:NVIDIA_VISIBLE_DEVICES } else { 'all' })
"@ | Set-Content -Path $EnvFile -Encoding utf8NoBOM

foreach ($dir in @('models', 'input', 'output', 'custom_nodes', 'user')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $ProjectDir (Join-Path $dataPath $dir)) | Out-Null
}

if ($SkipBuild) {
    Write-Host "Configuration written to $EnvFile; build skipped."
    exit 0
}

docker compose --env-file $EnvFile -f (Join-Path $ProjectDir 'compose.yaml') build --pull
& (Join-Path $PSScriptRoot 'verify.ps1')
if ($Start) {
    docker compose --env-file $EnvFile -f (Join-Path $ProjectDir 'compose.yaml') up -d
}
