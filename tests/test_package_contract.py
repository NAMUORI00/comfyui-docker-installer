import os
import re
import stat
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def service_block(compose: str, service: str) -> str:
    marker = f"  {service}:\n"
    start = compose.index(marker)
    next_service = re.search(r"\n  [a-zA-Z0-9_-]+:\n", compose[start + len(marker):])
    if next_service:
        return compose[start:start + len(marker) + next_service.start()]
    return compose[start:]


def test_expected_repository_files_exist():
    expected = [
        "Dockerfile",
        "compose.yaml",
        ".env.example",
        "extra_model_paths.yaml",
        "scripts/preflight.sh",
        "scripts/install.sh",
        "scripts/verify.sh",
        "scripts/uninstall.sh",
        "scripts/install.ps1",
        "scripts/verify.ps1",
        "scripts/uninstall.ps1",
        "scripts/tunnel.ps1",
        "README.md",
        "docs/a6000-2-preflight.md",
        "docs/compatibility.md",
        "docs/operations.md",
        ".gitignore",
    ]
    missing = [path for path in expected if not (ROOT / path).exists()]
    assert missing == []


def test_compose_routes_lan_access_through_caddy_basic_auth_proxy():
    compose = read("compose.yaml")
    comfyui = service_block(compose, "comfyui")
    caddy = service_block(compose, "caddy")
    assert "caddy:" in compose
    assert "image: caddy:2-alpine" in caddy
    assert '"${COMFYUI_BIND_HOST:-0.0.0.0}:${COMFYUI_HOST_PORT:-8188}:8188"' in caddy
    assert "${COMFYUI_DATA_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro" in caddy
    assert "reverse_proxy comfyui:8188" not in compose
    assert "ports:" not in comfyui
    assert "expose:" in comfyui
    assert '"8188"' in comfyui
    assert "depends_on:" in caddy
    assert "comfyui" in caddy
    assert "${COMFYUI_DATA_DIR}/models:/opt/comfyui-models" in comfyui
    assert "./extra_model_paths.yaml:/opt/ComfyUI/extra_model_paths.yaml:ro" in comfyui
    assert 'user: "${COMFYUI_USER_SPEC:-1000:1000}"' in comfyui
    assert "COMFYUI_REF: ${COMFYUI_REF:-master}" in comfyui
    assert "capabilities: [gpu]" in comfyui


def test_dockerfile_preserves_cuda_pytorch_and_uses_configurable_base():
    dockerfile = read("Dockerfile")
    assert "ARG COMFYUI_BASE_IMAGE=pytorch/pytorch:2.4.1-cuda12.1-cudnn9-runtime" in dockerfile
    assert "FROM ${COMFYUI_BASE_IMAGE}" in dockerfile
    assert "ARG COMFYUI_REF=master" in dockerfile
    assert "git checkout \"${COMFYUI_REF}\"" in dockerfile
    assert "comfyui-build-revision" in dockerfile
    assert "build-essential" in dockerfile
    assert "torch-constraints.txt" in dockerfile
    assert "torch.version.cuda" in dockerfile
    assert "if not torch.version.cuda:" in dockerfile
    assert "raise SystemExit" in dockerfile
    assert "else None" not in dockerfile
    assert "pip install --no-cache-dir --upgrade ninja" in dockerfile
    assert "pip check" in dockerfile
    assert "USER ${COMFYUI_UID}:${COMFYUI_GID}" in dockerfile


def test_env_defaults_match_a6000_2_preflight():
    env = read(".env.example")
    assert "COMFYUI_BASE_IMAGE=pytorch/pytorch:2.4.1-cuda12.1-cudnn9-runtime" in env
    assert "COMFYUI_REF=master" in env
    assert "COMFYUI_DATA_DIR=./data" in env
    assert "COMFYUI_BIND_HOST=0.0.0.0" in env
    assert "CADDY_AUTH_USER=yskim" in env
    assert "CADDY_AUTH_PASSWORD" not in env
    assert "auth.hash" not in env
    assert "COMFYUI_UID=" in env
    assert "COMFYUI_GID=" in env
    assert "COMFYUI_USER_SPEC=" in env
    assert "COMFYUI_HOST_PORT=8188" in env


def test_install_script_detects_environment_and_generates_caddy_auth_files():
    install = read("scripts/install.sh")
    assert "detect_base_image" in install
    assert "nvidia-smi" in install
    assert "535." in install
    assert "pytorch/pytorch:2.4.1-cuda12.1-cudnn9-runtime" in install
    assert "COMFYUI_BIND_HOST" in install
    assert "COMFYUI_REF=${COMFYUI_REF:-master}" in install
    assert "COMFYUI_BIND_HOST=${bind_host}" in install
    assert "CADDY_AUTH_USER=${auth_user}" in install
    assert "bind_host=\"${COMFYUI_BIND_HOST:-0.0.0.0}\"" in install
    assert "auth_user=\"${CADDY_AUTH_USER:-yskim}\"" in install
    assert "auth_hash_file=\"${COMFYUI_DATA_DIR}/caddy/auth.hash\"" in install
    assert "caddy hash-password" in install
    assert "printf '%s\\n' \"$password\"" in install
    assert "CADDY_AUTH_PASSWORD" in install
    assert "CADDY_AUTH_RESET" in install
    assert "reverse_proxy comfyui:8188" in install
    assert "basic_auth" in install
    assert "nvidia-ctk runtime configure --runtime=docker" in install
    assert "--apply-runtime-fix" in install
    assert "sudo -v" in install
    assert "sudo authentication" in install
    assert 'data_dir="${COMFYUI_DATA_DIR:-./data}"' in install
    assert "normalize_uid_gid" in install
    assert "id -u" in install
    assert "id -g" in install
    assert "Data directory is not writable" in install
    assert "chown -R" in install


def test_windows_scripts_generate_relative_data_path_and_no_uid_gid_by_default():
    install = read("scripts/install.ps1")
    verify = read("scripts/verify.ps1")
    uninstall = read("scripts/uninstall.ps1")
    assert "$DataDir = './data'" in install
    assert "COMFYUI_DATA_DIR=./data" in install
    assert "COMFYUI_BIND_HOST=$bindHost" in install
    assert "CADDY_AUTH_USER=$authUser" in install
    assert "auth.hash" in install
    assert "Caddyfile" in install
    assert "caddy hash-password" in install
    assert "CADDY_AUTH_PASSWORD" in install
    assert "'0.0.0.0'" in install
    assert "COMFYUI_REF=" in install
    assert "COMFYUI_UID=" in install
    assert "COMFYUI_GID=" in install
    assert "COMFYUI_USER_SPEC=" in install
    assert "docker compose config --quiet" in verify
    assert "torch.cuda.is_available()" in verify
    assert "CONFIRM_REMOVE_DATA" in uninstall


def test_verify_script_checks_gpu_compose_packages_and_ownership():
    verify = read("scripts/verify.sh")
    assert "torch.cuda.is_available()" in verify
    assert "docker compose config --quiet" in verify
    assert "pip check" in verify
    assert ".ownership-check" in verify
    assert "docker compose --env-file \"$ENV_FILE\" ps --format json" in verify
    assert "command -v python3" in verify
    assert "PUBLISHED_JSON" in verify
    assert "COMFYUI_BIND_HOST" in verify
    assert "published endpoint does not match" in verify
    assert 'published_port in {"", "0"}' in verify
    assert '"caddy"' in verify
    assert "ComfyUI is directly published" in verify


def test_docs_describe_failure_rollback_and_github_packaging():
    readme = read("README.md")
    operations = read("docs/operations.md")
    compatibility = read("docs/compatibility.md")
    combined = "\n".join([readme, operations, compatibility])
    for phrase in [
        "Failure criteria",
        "Rollback",
        "GitHub",
        "Basic Auth",
        "http://172.18.102.9:8188",
        "Docker daemon NVIDIA runtime",
        "CUDA 13",
    ]:
        assert phrase in combined


def test_shell_scripts_have_valid_syntax_and_executable_bits():
    for rel in [
        "scripts/preflight.sh",
        "scripts/install.sh",
        "scripts/verify.sh",
        "scripts/uninstall.sh",
    ]:
        path = ROOT / rel
        first_line = path.read_text(encoding="utf-8").splitlines()[0]
        assert first_line == "#!/usr/bin/env bash"
        if os.name != "nt":
            mode = path.stat().st_mode
            assert mode & stat.S_IXUSR, f"{rel} is not executable"
        result = subprocess.run(["bash", "-n", Path(rel).as_posix()], cwd=ROOT, text=True, capture_output=True)
        assert result.returncode == 0, result.stderr


def test_no_placeholders_or_incompatible_cuda13_defaults():
    forbidden = re.compile(r"(TBD|TODO|fill in|implement later|2\.9\.0-cuda13|cuda13\.0)", re.IGNORECASE)
    scanned = []
    for path in ROOT.rglob("*"):
        if path.is_file() and ".git" not in path.parts and path.suffix in {"", ".md", ".sh", ".yaml", ".example", ".ps1"}:
            scanned.append(path)
            assert not forbidden.search(path.read_text(encoding="utf-8")), str(path)
    assert scanned
