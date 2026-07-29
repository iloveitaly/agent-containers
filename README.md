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
  environment.json  # Cursor Cloud Agent install/start hooks
cursor/             # Cursor cloud-agent style image
  Dockerfile        # Ubuntu 24.04 LTS base
  install.sh        # Docker, zsh, ubuntu user, mise, direnv (+ /workspace trust)
  start.sh          # Start dockerd + open docker.sock for the session
Justfile            # local build recipes
```

## Install

On a fresh Ubuntu host (as root), run:

```bash
curl -fsSL https://raw.githubusercontent.com/iloveitaly/agent-containers/master/cursor/install.sh | bash
```

Requires `curl`, `gnupg`, and `ca-certificates`.

### Cursor Cloud Agents

Point `.cursor/environment.json` at the same curl one-liners so cloud agents get Docker, mise, and direnv on startup, then bring the daemon up each session:

```json
{
  "install": "curl -fsSL https://raw.githubusercontent.com/iloveitaly/agent-containers/master/cursor/install.sh | bash",
  "start": "curl -fsSL https://raw.githubusercontent.com/iloveitaly/agent-containers/master/cursor/start.sh | bash"
}
```

`install` only packages and configures Docker — it does not start the daemon. Cursor expects long-lived services in [`start`](https://cursor.com/docs/cloud-agent/setup#running-docker); without it, `docker` fails with a missing daemon.

`start.sh` starts dockerd and opens `/var/run/docker.sock` for the current session. `usermod -aG docker ubuntu` from `install.sh` does not take effect until a new login, so without the chmod agents still hit socket permission errors.

`install.sh` also installs **zsh** as the `ubuntu` user's default shell, and writes global mise/direnv config so anything under `/workspace` is trusted without `mise trust` or `direnv allow`.

This repo already includes that config under `.cursor/environment.json`. Copy the same snippet into other repos to reuse this environment without vendoring the scripts.

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
