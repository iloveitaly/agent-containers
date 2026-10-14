# Agent notes

## Cursor Cloud specific instructions

- `install` + `start` only (no Dockerfile).
- Keep [`.cursor/environment.json`](.cursor/environment.json) as `curl | bash` against `master`. Copy-paste for other projects; do not use `bash cursor/install.sh`.
- [`cursor/Dockerfile`](cursor/Dockerfile) is the Cursor-like base (`locales`, `xz-utils`, `tmux`, `python3`, `jq`, `ripgrep`, `unzip`, `git`, `sudo`). [`cursor/install.sh`](cursor/install.sh) is the overlay: Docker/mise/direnv, `libnss3-tools` (`certutil`) when missing, system mise config under `/etc/mise` (`uv`, `gh` only if missing, `MISE_ENV=dev,extras` in `/etc/mise/miserc.toml` + `/etc/zsh/zshenv` + `/etc/environment`, assumed [python-starter-template](https://github.com/iloveitaly/python-starter-template/) `.config/mise.dev.toml` / `.config/mise.extras.toml`), idempotent edits via global mise `pypi:lineinfile@latest`, and `iloveitaly/gh-ai-pr` via passwordless sudo. If `$PWD` has a `.envrc`, it runs `direnv allow` as `ubuntu`. If `$PWD` has a justfile, `mise which just` succeeds, and `setup` is defined, it runs `just setup --skip-services` as `ubuntu` via `mise exec -- direnv exec .` when `just --usage setup` lists that flag (otherwise `just setup`). It does not install `just`. `OP_INTEGRATION_DISABLED=1` is set only in the install process environment (not persisted, not used by `start.sh`) so `op` does not wait on the 1Password app during snapshot setup. That `--skip-services` run is the environment snapshot. [`cursor/start.sh`](cursor/start.sh) starts dockerd on every container run, then runs `just setup` as `ubuntu` through the same `mise exec -- direnv exec .` path when a setup recipe exists.

## mise documentation

Markdown source for mise docs: https://github.com/jdx/mise/tree/main/docs
