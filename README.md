# agent-containers

Agent runtime containers for coding harnesses (Cursor first; more later).

## Why this exists

Most agent images ship a language toolchain or a thin OS layer. This project is different: every image installs **Docker**, **mise**, and **direnv**, and wires them into the default shell profile so agents land in a working environment without extra setup.

That means:

- **Docker** — docker-in-docker ready (fuse-overlayfs + iptables-legacy), so agents can build and run containers
- **mise** — language/tool version management with shell activation by default
- **direnv** — per-directory env loading, hooked *after* mise so PATH stays consistent

## Layout

```
cursor/           # Cursor cloud-agent style image
  Dockerfile      # Ubuntu 24.04 LTS base
  install.sh      # Docker, ubuntu user, mise, direnv
Justfile          # local build recipes
```

## Install

On a fresh Ubuntu host (as root / with sudo), run:

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/iloveitaly/agent-containers/master/cursor/install.sh)
```

Requires `curl`, `gnupg`, and `ca-certificates`.

## Build

```bash
just build-cursor
```

Produces `agent-container-cursor:local`.

## Smoke test

```bash
docker run --rm agent-container-cursor:local bash -lc '
  export HOME=/home/ubuntu
  eval "$(mise activate bash)"
  git clone --depth 1 https://github.com/iloveitaly/railpack.git /tmp/railpack
  cd /tmp/railpack
  mise trust && mise install && mise run build
'
```
