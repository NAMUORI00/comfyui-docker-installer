# A6000-2 Read-Only Preflight Report

Date: 2026-05-27

## Scope

This report records read-only checks performed against SSH alias `A6000_2`. No package installation, remote file creation, Docker image pull, image build, container start, or service restart was performed.

## Access

- SSH: works
- Remote user: `yskim`
- Hostname: `gpusystem`
- UID/GID: `1005:1006`
- Groups: `yskim sudo docker gpuUsers`
- Passwordless sudo: not available

## Host

- OS: Ubuntu 22.04.5 LTS
- Kernel: `5.15.0-153-generic`
- Architecture: `x86_64`
- CPU: 64 logical CPUs, Intel Xeon Gold 5416S, 2 sockets
- RAM: 251 GiB total, about 245 GiB available at check time
- Swap: 8 GiB

## Storage

- Root filesystem: ext4, 1.8 TiB total, 1.5 TiB used, 235 GiB available, 86% used
- `/home/yskim`: on root filesystem, owned by `yskim:yskim`
- `/opt`: owned by `root:root`
- `/data`: missing
- Recommendation: use `/home/yskim/comfyui-docker` for first deployment to avoid sudo-owned application data.

## GPU

- GPU count: 3
- GPU model: NVIDIA RTX A6000
- VRAM per GPU: 49140 MiB
- Driver: `535.261.03`
- CUDA reported by `nvidia-smi`: `12.2`
- GPU state at check time: idle, no running GPU processes

## Docker

- Docker Engine: `24.0.2`
- Docker Compose: `v2.18.1`
- Docker service: active and enabled
- Docker group access: user is in `docker`
- Docker root dir: `/var/lib/docker`
- Existing relevant images: none found for PyTorch, CUDA, or ComfyUI
- Existing relevant containers: none found for ComfyUI or port `8188`
- Port `8188`: free

## NVIDIA Container Runtime

- NVIDIA Container Toolkit: `1.17.8`
- `nvidia-container-runtime`: present
- Docker daemon runtime state: not configured for NVIDIA yet
- `/etc/docker/daemon.json`: absent
- `docker info` runtimes: only `runc` and `io.containerd.runc.v2`
- `nvidia-ctk runtime configure --runtime=docker --dry-run` shows the expected `nvidia` runtime config.
- Applying the runtime config requires sudo and Docker restart.

## Package Source Caveat

The host is Ubuntu Jammy, but Docker apt source currently points at Docker's Ubuntu Bionic repository:

```text
https://download.docker.com/linux/ubuntu bionic stable
```

Avoid Docker package upgrades until this is corrected or explicitly approved. The existing Docker engine is running, so first deployment can proceed without upgrading Docker if the NVIDIA runtime configuration is applied successfully.

## Feasibility Classification

Conditional pass.

The server is a strong fit for ComfyUI Docker deployment because SSH, GPU, memory, disk, Docker, Compose, and NVIDIA Container Toolkit are present. The blocking runtime issue is that Docker's NVIDIA runtime is installed but not registered in Docker daemon configuration.

## Security Exposure Plan

- Current state: port `8188` is not listening.
- Recommended binding: `127.0.0.1:8188:8188` in Docker Compose.
- Recommended access path: SSH tunnel only.
- Do not bind ComfyUI to `0.0.0.0:8188` or open it directly on the network unless a separate authenticated reverse proxy or private network plan is approved.
- Post-start verification: `ss -ltnp | grep ':8188'` should show a loopback listener, not a public listener.

## Persistent Data Plan

- Recommended deployment root: `/home/yskim/comfyui-docker`
- Recommended persistent data root: `/home/yskim/comfyui-docker/data`
- Models: `/home/yskim/comfyui-docker/data/models`
- Inputs: `/home/yskim/comfyui-docker/data/input`
- Outputs: `/home/yskim/comfyui-docker/data/output`
- Custom nodes: `/home/yskim/comfyui-docker/data/custom_nodes`
- User settings: `/home/yskim/comfyui-docker/data/user`
- Use `extra_model_paths.yaml` to point ComfyUI at the persistent model directory instead of hiding the image's built-in `/opt/ComfyUI/models` tree with a bind mount.

## Failure Criteria

Stop and report instead of continuing if any of these occur:

- Docker's NVIDIA runtime cannot be configured.
- `docker run --rm --gpus all ... torch.cuda.is_available()` is not `True`.
- Docker daemon restart is not approved or fails.
- Available disk drops below a practical threshold for the intended model set.
- Port `8188` is already occupied by a service the user wants to keep.
- ComfyUI would need public unauthenticated exposure to be usable.
- The selected PyTorch/CUDA image is incompatible with driver `535.261.03`.

## Rollback Plan

For the recommended home-directory deployment:

```bash
cd /home/yskim/comfyui-docker
docker compose down
```

This stops the service while preserving models, inputs, outputs, custom nodes, and user settings under `/home/yskim/comfyui-docker/data`.

Only after separate explicit confirmation, remove the local image:

```bash
docker image rm comfyui-a6000:local
```

Only after separate explicit destructive confirmation, remove all deployment files and persistent data:

```bash
rm -rf /home/yskim/comfyui-docker
```

## Required Next Approval

Before building or starting ComfyUI, approve one privileged runtime repair step:

```bash
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

After that, verify:

```bash
docker info --format '{{json .Runtimes}} {{.DefaultRuntime}}'
docker run --rm --gpus all pytorch/pytorch:2.4.1-cuda12.1-cudnn9-runtime python -c 'import torch; print(torch.__version__); print(torch.cuda.is_available()); print(torch.cuda.get_device_name(0) if torch.cuda.is_available() else "NO_CUDA")'
```

The recommended default base image is `pytorch/pytorch:2.4.1-cuda12.1-cudnn9-runtime`, because the host driver reports CUDA 12.2. CUDA 13 images should not be used unless the NVIDIA driver is upgraded and retested.

## GitHub Packaging Implication

After ComfyUI is verified on this host, package the deployment as a GitHub repository with:

- `Dockerfile`
- `compose.yaml`
- `.env.example`
- `extra_model_paths.yaml`
- `scripts/preflight.sh`
- `scripts/verify.sh`
- `scripts/install.sh`
- `scripts/tunnel.ps1`
- `README.md`
- `docs/a6000-2-preflight.md`
- `docs/operations.md`

The package should default to relative `./data` mounts, Linux UID/GID `1005:1006` when generated on A6000-2, localhost-only port binding, SSH tunnel access, and CUDA 12.1 PyTorch image for this server profile.
