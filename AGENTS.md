# Agent notes

## Cursor Cloud specific instructions

- `install` + `start` only (no Dockerfile).
- Keep [`.cursor/environment.json`](.cursor/environment.json) as `curl | bash` against `master`. Copy-paste for other projects; do not use `bash cursor/install.sh`.
- [`cursor/Dockerfile`](cursor/Dockerfile) is the Cursor-like base (`locales`, `xz-utils`, `tmux`, `python3`, `jq`, `ripgrep`, `unzip`, `git`, `sudo`). [`cursor/install.sh`](cursor/install.sh) is the overlay: Docker/mise/direnv via passwordless sudo. If `$PWD` has a justfile, `just` is on PATH (mise), and `setup` is defined, it runs `just setup` as `ubuntu`. It does not install `just`. [`cursor/start.sh`](cursor/start.sh) starts dockerd each boot.

## mise documentation

Markdown source for mise docs: https://github.com/jdx/mise/tree/main/docs
