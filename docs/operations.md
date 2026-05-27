# Operations

## Network Exposure

Only Caddy is bound to host interfaces by default. ComfyUI is reachable only on the Docker internal network:

```yaml
caddy:
  ports:
    - "${COMFYUI_BIND_HOST:-0.0.0.0}:${COMFYUI_HOST_PORT:-8188}:8188"

comfyui:
  expose:
    - "8188"
```

On A6000-2, open:

```text
http://172.18.102.9:8188
```

The browser prompts for Basic Auth before ComfyUI loads. Default username is `yskim`; set `CADDY_AUTH_USER` before running the installer to change it. The installer stores only the Caddy password hash in `data/caddy/auth.hash`.

For localhost-only Caddy access, set `COMFYUI_BIND_HOST=127.0.0.1` in `.env` and use an SSH tunnel:

```bash
ssh -N -L 8188:127.0.0.1:8188 A6000_2
```

Do not expose this port outside the trusted internal network without an authenticated reverse proxy or firewall rule.

HTTP Basic Auth does not encrypt credentials over plain HTTP. For credential confidentiality, add HTTPS, VPN, or SSO.

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
- Published endpoint for port `8188` matches `COMFYUI_BIND_HOST`.
- ComfyUI is not directly published; only the `caddy` service may publish port `8188`.

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
