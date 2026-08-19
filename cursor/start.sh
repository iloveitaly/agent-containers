#!/usr/bin/env bash
set -euo pipefail

# Cursor expects long-lived services in `start`, not `install`.
# See https://cursor.com/docs/cloud-agent/setup#running-docker
sudo service docker start

# dockerd can return before the socket exists; chmod would then fail and
# abort start (set -e). Wait, then open the socket for this session:
# usermod -aG docker from install.sh does not apply until a new login.
for i in $(seq 1 40); do
  if [ -S /var/run/docker.sock ]; then
    break
  fi
  echo "waiting for /var/run/docker.sock (${i}/40)" >&2
  sleep 0.25
done
if [ ! -S /var/run/docker.sock ]; then
  echo "docker.sock did not appear after waiting" >&2
  exit 1
fi
sudo chmod 666 /var/run/docker.sock
