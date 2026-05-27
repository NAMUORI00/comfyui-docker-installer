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

Default data path:

```text
./data
```

Subdirectories:

- `models`
- `input`
- `output`
- `custom_nodes`
- `user`

`extra_model_paths.yaml` maps persistent models to `/opt/comfyui-models` inside the container. This avoids hiding ComfyUI's built-in `/opt/ComfyUI/models` tree.

On Linux, run `scripts/install.sh` so `.env` gets the invoking user's UID/GID and `COMFYUI_USER_SPEC`. The installer creates data directories before Compose starts and fails early if they are not writable. On Windows, run `scripts/install.ps1`; UID/GID fields remain empty and the Compose default is used.

## Source Version

Default source ref:

```text
COMFYUI_REF=master
```

This tracks latest upstream ComfyUI. For reproducible installs, set `COMFYUI_REF` to a known tag or commit SHA before building.

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
- No non-localhost published endpoint for port `8188`.

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
