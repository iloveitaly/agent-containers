# agent-containers

Agent runtime containers for coding harnesses (Cursor first; more later).

## Why this exists

Most agent images ship a language toolchain or a thin OS layer. This project is different: every image installs **Docker**, **mise**, and **direnv**, and wires them into the default shell profile so agents land in a working environment without extra setup.

That means:

- **Docker** — docker-in-docker ready (fuse-overlayfs + iptables-legacy), so agents can build and run containers
- **zsh** — default shell for the `ubuntu` user (Justfiles and agent sessions expect it)
- **mise** — language/tool version management with shell activation by default; `/workspace` pre-trusted
- **direnv** — per-directory env loading, hooked *after* mise so PATH stays consistent; `/workspace` whitelisted

## Layout

```
.cursor/
  environment.json  # Cursor Cloud: Dockerfile base + start dockerd
cursor/             # Cursor cloud-agent style image
  Dockerfile        # Ubuntu 24.04 LTS; RUN install.sh as root
  install.sh        # Docker, zsh, ubuntu user, mise, direnv (+ /workspace trust)
  start.sh          # Start dockerd + open docker.sock for the session
Justfile            # local build recipes
```

## Install

On a fresh Ubuntu host, run as root (or as a user with passwordless sudo):

```bash
curl -fsSL https://raw.githubusercontent.com/iloveitaly/agent-containers/master/cursor/install.sh | bash
```

Requires `curl`, `gnupg`, `ca-certificates`, and `sudo` when not already root.

### Cursor Cloud Agents

Current Cursor docs ([Running Docker](https://cursor.com/docs/cloud-agent/setup#running-docker)) install Docker in the **environment Dockerfile** (root, image build), not in the Cloud `install` hook. `install` runs as `ubuntu` and cannot write `/etc/apt/keyrings/docker.gpg`. Nested Docker also needs `fuse-overlayfs` and `iptables-legacy`. Start the daemon per boot with `sudo service docker start` in `start` — Builds keep disk state only, not running processes.

This repo's [`.cursor/environment.json`](.cursor/environment.json) follows that layout: `build` points at [`cursor/Dockerfile`](cursor/Dockerfile) (which `RUN`s [`install.sh`](cursor/install.sh) as root), `install` is a no-op, and [`cursor/start.sh`](cursor/start.sh) starts dockerd.

`start.sh` waits for `/var/run/docker.sock` and `chmod`s it for the current session. `usermod -aG docker ubuntu` from image build does not apply until a new login, so without the chmod agents still hit socket permission errors.

`install.sh` also installs **zsh** as the `ubuntu` user's default shell, and writes global mise/direnv config so anything under `/workspace` is trusted without `mise trust` or `direnv allow`.

## Docker

Prebuilt multi-arch image (`linux/amd64`, `linux/arm64`) on GHCR:

```bash
docker pull ghcr.io/iloveitaly/ubuntu-docker-mise-direnv:latest
docker run --rm -it ghcr.io/iloveitaly/ubuntu-docker-mise-direnv:latest bash -l
```

## Build

```bash
just build-cursor
```

Produces `ubuntu-docker-mise-direnv:local`.

## Test

```bash
just test
```

Builds the image (if needed), then clones [railpack](https://github.com/iloveitaly/railpack) inside the container and runs `mise install` + `mise run build`.
