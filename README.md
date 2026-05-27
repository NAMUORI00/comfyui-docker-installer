# ComfyUI Docker Installer

Self-checking Docker package for running the latest ComfyUI source on NVIDIA GPU servers.

This repo was first profiled against `A6000_2`, an Ubuntu 22.04 host with 3 x NVIDIA RTX A6000 GPUs, NVIDIA driver `535.261.03`, Docker `24.0.2`, Compose `v2.18.1`, and NVIDIA Container Toolkit `1.17.8`.

## What It Does

- Detects the host GPU/driver environment before choosing the default PyTorch CUDA image.
- Builds ComfyUI from `COMFYUI_REF`, defaulting to latest `master` while allowing a tag or commit SHA for reproducible rebuilds.
- Generates a local `.env` with UID/GID, data path, port, and image settings.
- Exposes ComfyUI on `0.0.0.0:8188` by default so hosts on the internal network can connect.
- Stores models, inputs, outputs, custom nodes, and user settings outside the container.
- Uses `extra_model_paths.yaml` so persistent models do not hide ComfyUI's built-in model directory.
- Verifies CUDA, Docker Compose config, Python package consistency, and output ownership.

## Quick Start On A6000-2

Linux:

```bash
cd /home/yskim/project/comfyui-docker-installer
scripts/preflight.sh
scripts/install.sh --apply-runtime-fix
scripts/install.sh --start
```

Windows PowerShell with Docker Desktop:

```powershell
cd comfyui-docker-installer
.\scripts\install.ps1 -SkipBuild
docker compose build --pull
.\scripts\verify.ps1
docker compose up -d
```

If Docker's NVIDIA runtime is already configured, omit `--apply-runtime-fix`.

Open:

```text
http://172.18.102.9:8188
```

## Manual Workflow

```bash
scripts/preflight.sh
scripts/install.sh --skip-build
docker compose build --pull
scripts/verify.sh
docker compose up -d
```

For localhost-only access instead, set `COMFYUI_BIND_HOST=127.0.0.1` and connect through:

```bash
ssh -N -L 8188:127.0.0.1:8188 A6000_2
```

## Failure criteria

Stop and inspect before continuing if:

- Docker daemon NVIDIA runtime cannot be configured.
- `torch.cuda.is_available()` is not `True` inside the container.
- Docker daemon restart is not approved or fails.
- Port `8188` is already used by another service.
- Internal network firewall policy does not allow direct access to `8188`.
- The selected PyTorch/CUDA image is incompatible with the host driver.

## Rollback

Preserve data while stopping ComfyUI:

```bash
scripts/uninstall.sh
```

Remove the local image too:

```bash
scripts/uninstall.sh --remove-image
```

Delete persistent data only with explicit confirmation:

```bash
CONFIRM_REMOVE_DATA=yes scripts/uninstall.sh --remove-data
```

## GitHub Packaging

After the package is verified on A6000-2, this repo can be pushed to GitHub as the reusable installer package. Keep server-specific observations in `docs/a6000-2-preflight.md`; keep general behavior in `README.md`, `docs/compatibility.md`, and `docs/operations.md`.

## Paths And Permissions

The package defaults to relative host mounts:

```dotenv
COMFYUI_DATA_DIR=./data
COMFYUI_BIND_HOST=0.0.0.0
COMFYUI_REF=master
```

On Linux, `scripts/install.sh` fills `COMFYUI_UID`, `COMFYUI_GID`, and `COMFYUI_USER_SPEC` from `id -u` and `id -g`, creates the data directories before Docker can create them as root, and fails early if those directories are not writable. On Windows, `scripts/install.ps1` leaves UID/GID empty and lets Compose use its safe default user spec.

For reproducible rebuilds, set `COMFYUI_REF` to a ComfyUI tag or commit SHA before running the installer. The default `master` tracks the latest upstream source.
