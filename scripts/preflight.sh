#!/usr/bin/env bash
set -u

echo "== identity =="
printf 'user=%s host=%s uid=%s gid=%s groups=%s\n' "$(whoami)" "$(hostname)" "$(id -u)" "$(id -g)" "$(id -Gn)"

echo "== host =="
uname -a
cat /etc/os-release 2>/dev/null || true

echo "== memory =="
free -h || true

echo "== storage =="
df -hT "$HOME" . /var/lib/docker 2>/dev/null || df -hT || true

echo "== gpu =="
nvidia-smi 2>&1 || true

echo "== docker =="
docker --version 2>&1 || true
docker compose version 2>&1 || true
docker info --format 'Runtimes={{json .Runtimes}} DefaultRuntime={{.DefaultRuntime}} DockerRootDir={{.DockerRootDir}}' 2>&1 || true

echo "== nvidia-container-runtime =="
nvidia-ctk --version 2>&1 || true
command -v nvidia-container-runtime || true
nvidia-container-runtime --version 2>&1 || true

echo "== port 8188 =="
ss -ltnp 2>/dev/null | grep ':8188' || true

echo "== docker apt source =="
grep -R "download.docker.com" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null || true
