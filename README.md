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
.cursor/
  environment.json  # Cursor Cloud Agent install hook
cursor/             # Cursor cloud-agent style image
  Dockerfile        # Ubuntu 24.04 LTS base
  install.sh        # Docker, ubuntu user, mise, direnv
Justfile            # local build recipes
```

## Install

On a fresh Ubuntu host (as root), run:

```bash
curl -fsSL https://raw.githubusercontent.com/iloveitaly/agent-containers/master/cursor/install.sh | bash
```

Requires `curl`, `gnupg`, and `ca-certificates`.

### Cursor Cloud Agents

Point `.cursor/environment.json` at the same one-liner so cloud agents get Docker, mise, and direnv on startup:

```json
{
  "install": "curl -fsSL https://raw.githubusercontent.com/iloveitaly/agent-containers/master/cursor/install.sh | bash"
}
```

This repo already includes that config under `.cursor/environment.json`. Copy the same snippet into other repos to reuse this environment without vendoring the scripts.

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
