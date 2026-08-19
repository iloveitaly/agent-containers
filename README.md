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
  environment.json  # Cursor Cloud install + start (no Dockerfile)
cursor/             # Cursor cloud-agent style image
  Dockerfile        # Ubuntu 24.04 LTS; RUN install.sh as root (GHCR / local just)
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

This repo ships [`.cursor/environment.json`](.cursor/environment.json) with **only** `install` and `start` (no `build.dockerfile`). Both commands `curl | bash` the scripts from `master` so you can copy that file into other repos without vendoring `cursor/`.

[`cursor/install.sh`](cursor/install.sh) re-execs with passwordless `sudo` so it can write Docker's apt key under `/etc/apt/keyrings` (otherwise `gpg --dearmor` fails with `Permission denied`). It also installs **zsh**, **mise**, and **direnv**, and trusts `/workspace`.

[`cursor/start.sh`](cursor/start.sh) runs `sudo service docker start`, waits for `/var/run/docker.sock`, and `chmod`s it for the current session. `usermod -aG docker ubuntu` from install does not apply until a new login. Builds keep disk state only, so the daemon must start in `start`.

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
