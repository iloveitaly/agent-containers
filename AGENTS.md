# Agent notes

## Cursor Cloud specific instructions

- `install` + `start` only (no Dockerfile).
- Keep [`.cursor/environment.json`](.cursor/environment.json) as `curl | bash` against `master`. Copy-paste for other projects; do not use `bash cursor/install.sh`.
- [`cursor/install.sh`](cursor/install.sh) installs Docker/mise/direnv via passwordless sudo, plus Cursor-default extras (`locales`, `xz-utils`, `tmux`, `python3`, `jq`, `ripgrep`, `unzip`) when missing. If a justfile exists at `/workspace` or `$PWD` and defines `setup`, it runs `just setup` as `ubuntu`. [`cursor/start.sh`](cursor/start.sh) starts dockerd each boot.

## mise documentation

Markdown source for mise docs: https://github.com/jdx/mise/tree/main/docs
