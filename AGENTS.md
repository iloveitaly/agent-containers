# Agent notes

## Cursor Cloud specific instructions

- `install` + `start` only (no Dockerfile).
- Keep [`.cursor/environment.json`](.cursor/environment.json) as `curl | bash` against `master`. Copy-paste for other projects; do not use `bash cursor/install.sh`.
- [`cursor/Dockerfile`](cursor/Dockerfile) is the Cursor-like base (`locales`, `xz-utils`, `tmux`, `python3`, `jq`, `ripgrep`, `unzip`, `git`, `sudo`). [`cursor/install.sh`](cursor/install.sh) is the overlay: Docker/mise/direnv, global mise `uv`, `gh` via mise only if missing, `MISE_ENV=dev,extras` (assumed [python-starter-template](https://github.com/iloveitaly/python-starter-template/) `.config/mise.dev.toml` and `.config/mise.extras.toml`), and `iloveitaly/gh-ai-pr` via passwordless sudo. If `$PWD` has a `.envrc`, it runs `direnv allow` as `ubuntu`. If `$PWD` has a justfile, `mise which just` succeeds, and `setup` is defined, it runs `just setup --skip-services` as `ubuntu` via `with_mise_and_direnv` when `just --usage setup` lists that flag (otherwise `just setup`; `mise activate`, then `direnv exec` when `.envrc` is present). It does not install `just`. `OP_INTEGRATION_DISABLED=1` is set before those project commands (and persisted for the `ubuntu` user) so `op` does not wait on the 1Password app. That `--skip-services` run is the environment snapshot. [`cursor/start.sh`](cursor/start.sh) starts dockerd on every container run, then runs `just setup` as `ubuntu` through the same mise and direnv path when a setup recipe exists.

## mise documentation

Markdown source for mise docs: https://github.com/jdx/mise/tree/main/docs
