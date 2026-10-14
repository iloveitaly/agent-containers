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

# install.sh runs `just setup --skip-services` while the snapshot is built.
# Run the recipe here on container start. Same ubuntu + mise + direnv path
# as install.sh; duplicated because Cursor curls each script on its own.
export OP_INTEGRATION_DISABLED=1

as_ubuntu() {
  sudo -n -u ubuntu -H env OP_INTEGRATION_DISABLED=1 "$@"
}

as_ubuntu_in_project() {
  as_ubuntu bash -c 'cd "$1" && shift && exec "$@"' bash "$PWD" "$@"
}

with_mise_and_direnv() {
  as_ubuntu bash -c '
    set -euo pipefail
    cd "$1" || exit 1
    shift
    eval "$(mise activate bash)"
    export OP_INTEGRATION_DISABLED=1
    if [ -f .envrc ]; then
      exec direnv exec . "$@"
    fi
    exec "$@"
  ' bash "$PWD" "$@"
}

if [ -f .envrc ]; then
  echo "Trusting .envrc in $PWD"
  as_ubuntu_in_project direnv allow .
fi

if [ -f justfile ] || [ -f Justfile ] || [ -f .justfile ]; then
  if as_ubuntu_in_project mise which just >/dev/null 2>&1; then
    if as_ubuntu_in_project mise exec -- just --show setup >/dev/null 2>&1; then
      echo "Running just setup in $PWD"
      with_mise_and_direnv just setup
    else
      echo "justfile found in $PWD but no setup recipe; skipping"
    fi
  else
    echo "justfile found in $PWD but just is not installed via mise; skipping just setup"
  fi
fi
