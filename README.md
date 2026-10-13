# agent-containers

Agent runtime containers for coding harnesses (Cursor first; more later).

## Why this exists

Most agent images ship a language toolchain or a thin OS layer. This project is different: every image installs **Docker**, **mise**, and **direnv**, and wires them into the default shell profile so agents land in a working environment without extra setup.

That means:

- **Docker** — docker-in-docker ready (fuse-overlayfs + iptables-legacy), so agents can build and run containers
- **zsh** — default shell for the `ubuntu` user (Justfiles and agent sessions expect it)
- **mise** — language/tool version management with shell activation by default; `/workspace` pre-trusted; [`uv`](https://docs.astral.sh/uv/) is a global mise tool, and [`gh`](https://cli.github.com/) is added only when it is not already on `PATH`. `MISE_ENV=dev,extras` is exported for the `ubuntu` user (and set in `~/.config/mise/miserc.toml`). That selection is tied to the assumed config of [python-starter-template](https://github.com/iloveitaly/python-starter-template/) (`.config/mise.dev.toml` and `.config/mise.extras.toml`).
- **direnv** — per-directory env loading, hooked *after* mise so PATH stays consistent; `/workspace` whitelisted, and a project `.envrc` is `direnv allow`ed once direnv is installed
- **just setup** — if the repo has a justfile with a `setup` recipe **and** `mise which just` succeeds, `install.sh` runs `just setup --skip-services` as `ubuntu` via `with_mise_and_direnv` when `just --usage setup` lists that flag (otherwise `just setup`; mise activate, then `direnv exec` when `.envrc` is present). It does not install `just`. `OP_INTEGRATION_DISABLED=1` is exported before direnv, mise, and that recipe (and written to the `ubuntu` shell rc and `/etc/environment`) so `op` does not wait on the 1Password desktop app. The flag skips docker compose and DB seed while the environment snapshot is built. `start.sh` starts dockerd on every container run, then runs `just setup` through the same mise and direnv path.
- **Cursor-like base** — `cursor/Dockerfile` (GHCR) installs the CLIs the hosted Cloud Agent VM already has: `git`, `sudo`, `locales` (`en_US.UTF-8`), `xz-utils`, `tmux`, `python3`, `jq`, `ripgrep`, `unzip`. Not in `install.sh`, so Cursor Cloud `curl | bash` does not reinstall them.
- **gh-ai-pr** — [`iloveitaly/gh-ai-pr`](https://github.com/iloveitaly/gh-ai-pr) GitHub CLI extension for the `ubuntu` user

## Layout

```
.cursor/
  environment.json  # Cursor Cloud install + start (no Dockerfile)
cursor/             # Cursor cloud-agent style image
  Dockerfile        # Cursor-like Ubuntu 24.04 base + RUN install.sh (GHCR / local just)
  install.sh        # Docker, zsh, ubuntu user, mise (+ global uv, gh if missing, MISE_ENV=dev,extras), direnv (+ /workspace whitelist and direnv allow), gh-ai-pr
  start.sh          # Start dockerd, open docker.sock, then full `just setup`
Justfile            # local build recipes
```

## Install

On a fresh Ubuntu host, run as root (or as a user with passwordless sudo):

```bash
curl -fsSL https://raw.githubusercontent.com/iloveitaly/agent-containers/master/cursor/install.sh | bash
```

Requires `curl`, `gnupg`, `ca-certificates`, and `sudo` when not already root.

### Cursor Cloud Agents

Copy [`.cursor/environment.json`](.cursor/environment.json) into other repos. It has **only** `install` and `start` (no `build.dockerfile`) and `curl | bash`s the scripts from `master`.

[`cursor/Dockerfile`](cursor/Dockerfile) is the Cursor-like base image (Ubuntu 24.04 plus `git`, `sudo`, `locales`, `xz-utils`, `tmux`, `python3`, `jq`, `ripgrep`, `unzip`). [`cursor/install.sh`](cursor/install.sh) is the overlay: it re-execs with passwordless `sudo` so it can write Docker's apt key under `/etc/apt/keyrings` (otherwise `gpg --dearmor` fails with `Permission denied`). It installs **Docker**, **zsh**, **mise**, and **direnv** when missing, installs **uv** as a global mise tool (`~/.config/mise/config.toml`), adds **gh** to that config only when `gh` is not already on `PATH`, exports `MISE_ENV=dev,extras` (also `~/.config/mise/miserc.toml`) for the assumed [python-starter-template](https://github.com/iloveitaly/python-starter-template/) mise environments (`.config/mise.dev.toml`, `.config/mise.extras.toml`), installs the [`iloveitaly/gh-ai-pr`](https://github.com/iloveitaly/gh-ai-pr) extension as `ubuntu`, and trusts `/workspace`. After that, if the app directory (`$PWD`) has a `.envrc`, it runs `direnv allow` as `ubuntu`. If that directory has a justfile, `mise which just` succeeds, and a `setup` recipe exists, it runs `just setup --skip-services` as `ubuntu` via `with_mise_and_direnv` when `just --usage setup` lists that flag (otherwise `just setup`; `mise activate`, then `direnv exec` when `.envrc` is present). It does not install `just`; without it, the recipe is skipped. `OP_INTEGRATION_DISABLED=1` is set before direnv, mise, and `just setup`, and persisted on the `ubuntu` shell rc and `/etc/environment`.

[`cursor/start.sh`](cursor/start.sh) runs `sudo service docker start`, waits for `/var/run/docker.sock`, and `chmod`s it for the current session. `usermod -aG docker ubuntu` from install does not apply until a new login. Builds keep disk state only, so the daemon must start in `start`. After the socket is ready, if the app directory has a justfile, `mise which just` succeeds, and a `setup` recipe exists, it runs `just setup` as `ubuntu` (mise activate, then `direnv exec` when `.envrc` is present). `OP_INTEGRATION_DISABLED=1` is set for that command.

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
just test-just-setup
just test
```

`test-just-setup` rebuilds the image and re-runs `install.sh` against fixtures: no justfile, a justfile without `setup`, a `setup` recipe with `just` missing from mise (skipped), a `setup` recipe with `just` already installed via mise (the marker is `OP_INTEGRATION_DISABLED`), a `setup` recipe that lists `--skip-services` (the marker is that flag's value), and a `setup` recipe whose `.envrc` lives outside the `/workspace` direnv whitelist (the marker is that file's value plus `OP_INTEGRATION_DISABLED`). It then runs `start.sh` (privileged, so dockerd starts) against a `setup` recipe that lists `--skip-services`, with an `.envrc` outside `/workspace`. The start marker is that file's value, `OP_INTEGRATION_DISABLED`, and the flag left at its default, because start runs `just setup`.

`just test` includes that hook, then clones [railpack](https://github.com/iloveitaly/railpack) inside the container and runs `mise install` + `mise run build`.
