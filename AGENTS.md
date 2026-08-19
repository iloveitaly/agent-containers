# Agent notes

## Cursor Cloud specific instructions

Docker is installed in [`cursor/Dockerfile`](cursor/Dockerfile) (via `install.sh` as root). Do not install Docker in the Cloud `install` hook. Per boot, [`cursor/start.sh`](cursor/start.sh) runs `sudo service docker start`. See [Running Docker](https://cursor.com/docs/cloud-agent/setup#running-docker).

## mise documentation

Markdown source for mise docs: https://github.com/jdx/mise/tree/main/docs
