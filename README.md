# agent-containers

Agent runtime containers for coding harnesses (Cursor first; more later).

## Why this exists

Most agent images ship a language toolchain or a thin OS layer. This project is different: every image installs **Docker**, **mise**, and **direnv**, and wires them into the default shell profile so agents land in a working environment without extra setup.

That means:

- **Docker** — docker-in-docker ready (fuse-overlayfs + iptables-legacy), so agents can build and run containers
- **zsh** — default shell for the `ubuntu` user (Justfiles and agent sessions expect it)
- **mise** — language/tool version management with shell activation by default; `/workspace` pre-trusted via **system** config (`/etc/mise/config.toml`); [`uv`](https://docs.astral.sh/uv/) is a global mise tool, and [`gh`](https://cli.github.com/) is added only when it is not already on `PATH`. `MISE_ENV=dev,extras` is set in `/etc/mise/miserc.toml`, `/etc/zsh/zshenv`, and `/etc/environment` so it survives a home-directory rsync. That selection is tied to the assumed config of [python-starter-template](https://github.com/iloveitaly/python-starter-template/) (`.config/mise.dev.toml` and `.config/mise.extras.toml`).
- **direnv** — per-directory env loading, hooked *after* mise so PATH stays consistent; `/workspace` whitelisted, and a project `.envrc` is `direnv allow`ed once direnv is installed
- **dotfiles** — after mise is on `/usr/local/bin`, `install.sh` runs [`iloveitaly/dotfiles`](https://github.com/iloveitaly/dotfiles) `install/linux-devbox.sh` as `ubuntu` (`DOTFILES_REF`, default `master`). It does not install a second mise. The rsync replaces the direnv config; `/workspace` is whitelisted again afterward. `/etc/mise` and `/etc/zsh/zshenv` stay in place.
- **just setup** — if the repo has a justfile with a `setup` recipe, **just is declared in the project mise config** (`mise.toml`, `.mise.toml`, or `.config/mise.toml`), and `mise which just` succeeds, `install.sh` runs `just setup --skip-services` as `ubuntu` via `mise exec -- direnv exec .` when `just --usage setup` lists that flag (otherwise `just setup`). `linux-devbox.sh` installs `just` globally; that does not by itself run `setup`. During **install only**, `OP_INTEGRATION_DISABLED=1` is exported in the process environment so `op` does not wait on the 1Password desktop app; it is not written to shell rc, `/etc/environment`, or used by `start.sh`. The flag skips docker compose and DB seed while the environment snapshot is built. `start.sh` starts dockerd on every container run, then runs `just setup` through the same `mise exec -- direnv exec .` path when the project declares `just`.
- **Cursor-like base** — `cursor/Dockerfile` (GHCR) installs the CLIs the hosted Cloud Agent VM already has: `git`, `sudo`, `locales` (`en_US.UTF-8`), `xz-utils`, `tmux`, `python3`, `jq`, `ripgrep`, `unzip`. Not in `install.sh`, so Cursor Cloud `curl | bash` does not reinstall them.
- **gh-ai-pr** — [`iloveitaly/gh-ai-pr`](https://github.com/iloveitaly/gh-ai-pr) GitHub CLI extension for the `ubuntu` user

## Layout

```
.cursor/
  environment.json  # Cursor Cloud install + start (no Dockerfile)
cursor/             # Cursor cloud-agent style image
  Dockerfile        # Cursor-like Ubuntu 24.04 base + RUN install.sh (GHCR / local just)
  install.sh        # Docker, zsh, libnss3-tools (certutil) + empty ~/.pki/nssdb, ubuntu user, system mise (/etc/mise + /etc/zsh/zshenv), direnv, linux-devbox.sh, gh-ai-pr
  start.sh          # Start dockerd, open docker.sock, then full `just setup`
Justfile            # local build recipes
```

## Install

On a fresh Ubuntu host, run as root (or as a user with passwordless sudo):

```bash
curl -fsSL https://raw.githubusercontent.com/iloveitaly/agent-containers/master/cursor/install.sh | bash
```

Requires `curl`, `ca-certificates`, and `sudo` when not already root.

### Cursor Cloud Agents

Copy [`.cursor/environment.json`](.cursor/environment.json) into other repos. It has **only** `install` and `start` (no `build.dockerfile`) and `curl | bash`s the scripts from `master`.

[`cursor/Dockerfile`](cursor/Dockerfile) is the Cursor-like base image (Ubuntu 24.04 plus `git`, `sudo`, `locales`, `xz-utils`, `tmux`, `python3`, `jq`, `ripgrep`, `unzip`). [`cursor/install.sh`](cursor/install.sh) is the overlay: it re-execs with passwordless `sudo` so it can write Docker's apt key under `/etc/apt/keyrings`. It installs **Docker**, **zsh**, **mise**, and **direnv** when missing, installs **libnss3-tools** (`certutil`) when missing (Cursor's default image has `libnss3` but not the tools package), initializes an empty shared NSS DB at `~/.pki/nssdb` for the `ubuntu` user when `cert9.db` is absent (needed by localias / Chromium; the package alone does not create it), installs **uv** as a system mise tool (`/etc/mise/config.toml`), adds **gh** to that config only when `gh` is not already on `PATH`, sets `MISE_ENV=dev,extras` in `/etc/mise/miserc.toml`, `/etc/zsh/zshenv`, and `/etc/environment` (idempotent edits via global mise `pypi:lineinfile@latest`, with every `mise install` / `mise exec` run as `ubuntu` so tools never install as root) for the assumed [python-starter-template](https://github.com/iloveitaly/python-starter-template/) mise environments (`.config/mise.dev.toml`, `.config/mise.extras.toml`), installs the [`iloveitaly/gh-ai-pr`](https://github.com/iloveitaly/gh-ai-pr) extension as `ubuntu`, and trusts `/workspace`. After that, if the app directory (`$PWD`) has a `.envrc`, it runs `direnv allow` as `ubuntu`. If that directory has a justfile, the project mise config declares `just`, `mise which just` succeeds, and a `setup` recipe exists, it runs `just setup --skip-services` as `ubuntu` via `mise exec -- direnv exec .` when `just --usage setup` lists that flag (otherwise `just setup`). It does not install `just` itself. It then runs `install/linux-devbox.sh` from [iloveitaly/dotfiles](https://github.com/iloveitaly/dotfiles) as `ubuntu`, which installs `just` globally, and restores the `/workspace` direnv whitelist after that rsync. `just setup` runs only when the project mise config declares `just`. Image builds without a logged-in `gh` need `MISE_GITHUB_TOKEN` or `GITHUB_TOKEN` (BuildKit secret `github_token`); Cursor Cloud already satisfies `mise token github` via `~/.config/gh/hosts.yml`. `OP_INTEGRATION_DISABLED=1` is set only in the install process environment (not persisted).

[`cursor/start.sh`](cursor/start.sh) starts `dockerd` if not already running, waits for `docker info` to succeed, and `chmod`s `/var/run/docker.sock` for the current session. `usermod -aG docker ubuntu` from install does not apply until a new login. Builds keep disk state only, so the daemon must start in `start`. After the daemon is ready, if the app directory has a justfile, the project mise config declares `just`, `mise which just` succeeds, and a `setup` recipe exists, it runs `just setup` as `ubuntu` via `mise exec -- direnv exec .`.

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

`test-just-setup` rebuilds the image (`MISE_GITHUB_TOKEN` or `GITHUB_TOKEN` required) and re-runs `install.sh` against fixtures: no justfile, a justfile without `setup`, a `setup` recipe whose project mise config does not declare `just` (skipped even though dotfiles installed `just` globally), a `setup` recipe with `just` declared in mise (the marker is install-time `OP_INTEGRATION_DISABLED`), a `setup` recipe that lists `--skip-services` (the marker is that flag's value), and a `setup` recipe whose `.envrc` lives outside the `/workspace` direnv whitelist (the marker is that file's value plus install-time `OP_INTEGRATION_DISABLED`). It then runs `start.sh` (privileged, so dockerd starts) against a `setup` recipe that lists `--skip-services`, with an `.envrc` outside `/workspace`. The start marker is that file's value, an empty `OP_INTEGRATION_DISABLED` (not set at start), and the skip-services flag left at its default.

`just test` includes that hook, then clones [railpack](https://github.com/iloveitaly/railpack) inside the container and runs `mise install` + `mise run build`.
