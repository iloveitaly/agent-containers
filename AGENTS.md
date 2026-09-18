# Agent notes

## Cursor Cloud specific instructions

- `install` + `start` only (no Dockerfile).
- Keep [`.cursor/environment.json`](.cursor/environment.json) as `curl | bash` against `master`. Copy-paste for other projects; do not use `bash cursor/install.sh`.
- [`cursor/Dockerfile`](cursor/Dockerfile) is the Cursor-like base (`locales`, `xz-utils`, `tmux`, `python3`, `jq`, `ripgrep`, `unzip`, `git`, `sudo`). [`cursor/install.sh`](cursor/install.sh) is the overlay: Docker/mise/direnv, global mise `uv`, `gh` via mise only if missing, and `iloveitaly/gh-ai-pr` via passwordless sudo. If `$PWD` has a justfile, `mise which just` succeeds, and `setup` is defined, it runs `mise exec -- just setup` as `ubuntu`. It does not install `just`. [`cursor/start.sh`](cursor/start.sh) starts dockerd each boot.

## mise documentation

Markdown source for mise docs: https://github.com/jdx/mise/tree/main/docs
