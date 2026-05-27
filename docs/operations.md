# Operations

## Security Exposure

ComfyUI is bound to localhost only:

```yaml
ports:
  - "127.0.0.1:${COMFYUI_HOST_PORT:-8188}:8188"
```

Use an SSH tunnel:

```bash
ssh -N -L 8188:127.0.0.1:8188 A6000_2
```

Do not expose ComfyUI on `0.0.0.0:8188` unless a separate authenticated reverse proxy or private network plan is approved.

## Persistent Data

Default A6000-2 data path:

```text
/home/yskim/project/comfyui-docker-installer/data
```

Subdirectories:

- `models`
- `input`
- `output`
- `custom_nodes`
- `user`

`extra_model_paths.yaml` maps persistent models to `/opt/comfyui-models` inside the container. This avoids hiding ComfyUI's built-in `/opt/ComfyUI/models` tree.

## Verification

Run:

```bash
scripts/verify.sh
```

It checks:

- Docker Compose config syntax.
- Host GPU visibility.
- `torch.cuda.is_available()` inside the container.
- Python package consistency through `pip check`.
- Output file ownership.
- No public `0.0.0.0:8188` listener.

## Failure criteria

Stop if:

- Docker daemon NVIDIA runtime cannot be configured.
- GPU is not visible inside the container.
- Selected CUDA/PyTorch image is incompatible with the host driver.
- Port `8188` conflicts with an existing service.
- Available disk is insufficient for the intended model set.

## Rollback

Stop service and preserve data:

```bash
scripts/uninstall.sh
```

Remove image:

```bash
scripts/uninstall.sh --remove-image
```

Remove persistent data only after explicit confirmation:

```bash
CONFIRM_REMOVE_DATA=yes scripts/uninstall.sh --remove-data
```
