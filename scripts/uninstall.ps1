param(
    [switch]$RemoveImage,
    [switch]$RemoveData
)

$ErrorActionPreference = 'Stop'
$ProjectDir = Resolve-Path (Join-Path $PSScriptRoot '..')
$EnvFile = Join-Path $ProjectDir '.env'

Push-Location $ProjectDir
try {
    docker compose down
    if ($RemoveImage) {
        docker image rm comfyui-a6000:local
    }
    if ($RemoveData) {
        if ($env:CONFIRM_REMOVE_DATA -ne 'yes') {
            throw 'Set CONFIRM_REMOVE_DATA=yes to delete persistent data.'
        }
        Remove-Item -Recurse -Force -LiteralPath (Join-Path $ProjectDir 'data')
    }
}
finally {
    Pop-Location
}
