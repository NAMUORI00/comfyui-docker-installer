# Compatibility

## A6000-2 Baseline

- OS: Ubuntu 22.04.5 LTS
- GPU: 3 x NVIDIA RTX A6000
- Driver: `535.261.03`
- CUDA reported by `nvidia-smi`: `12.2`
- Docker: `24.0.2`
- Docker Compose: `v2.18.1`
- NVIDIA Container Toolkit: `1.17.8`

For this baseline, the default image is:

```text
pytorch/pytorch:2.4.1-cuda12.1-cudnn9-runtime
```

## Image Selection Policy

`scripts/install.sh` uses `nvidia-smi` to select a base image.

- Driver `535.*`: use CUDA 12.1 PyTorch runtime.
- CUDA major `12`, minor at least `1`: use CUDA 12.1 PyTorch runtime.
- CUDA major `13`: use a CUDA 13 PyTorch runtime only after the host driver supports it.

CUDA 13 is intentionally not the default for A6000-2. The observed driver reports CUDA 12.2, so a CUDA 13 image would be an avoidable compatibility risk.

## Docker Runtime Requirement

Docker must list an `nvidia` runtime in:

```bash
docker info --format '{{json .Runtimes}} {{.DefaultRuntime}}'
```

If NVIDIA Container Toolkit is installed but Docker does not list the runtime, run after approval:

```bash
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

## Windows And Linux Entry Points

- Linux: `scripts/install.sh`, `scripts/preflight.sh`, `scripts/verify.sh`, `scripts/uninstall.sh`
- Windows PowerShell: `scripts/install.ps1`, `scripts/verify.ps1`, `scripts/uninstall.ps1`, `scripts/tunnel.ps1`

Host data mounts default to `./data` on both platforms. Network binding defaults to `COMFYUI_BIND_HOST=0.0.0.0` so internal network clients can connect to Caddy. Caddy applies Basic Auth and proxies to ComfyUI on the Docker internal network; set `COMFYUI_BIND_HOST=127.0.0.1` for SSH-tunnel-only operation. Linux installation dynamically writes UID/GID values into `.env`; Windows installation leaves UID/GID blank and relies on Compose defaults. Custom node Python packages install into `data/python`, exposed as `PYTHONUSERBASE=/opt/comfyui-python`.

`COMFYUI_REF` defaults to `master` so normal installs track latest upstream ComfyUI. Set it to a tag or commit SHA when reproducible rebuilds are more important than latest-source tracking.

## Docker Package Source Caveat

On A6000-2, the host is Ubuntu Jammy while Docker's apt source points at Bionic. Do not upgrade Docker packages as part of this installer. Fix package sources separately if Docker upgrades are needed.
