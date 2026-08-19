# Agent notes

## Cursor Cloud specific instructions

This environment uses `install` + `start` only (no Dockerfile).

Keep [`.cursor/environment.json`](.cursor/environment.json) as `curl | bash` against `master` on this repo. That file is the copy-paste snippet for other projects; do not replace it with `bash cursor/install.sh` (those paths only exist in this repo).

[`cursor/install.sh`](cursor/install.sh) installs Docker/mise/direnv via passwordless sudo. [`cursor/start.sh`](cursor/start.sh) starts dockerd each boot.

## mise documentation

Markdown source for mise docs: https://github.com/jdx/mise/tree/main/docs
