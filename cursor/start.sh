#!/usr/bin/env bash
set -euo pipefail

# Cursor expects long-lived services in `start`, not `install`.
# See https://cursor.com/docs/cloud-agent/setup#running-docker
if ! sudo docker info >/dev/null 2>&1; then
  sudo service docker start
fi

# dockerd can return before the socket is ready; wait for the daemon, then open
# the socket for this session (usermod -aG docker from install.sh does not
# apply until a new login).
for i in $(seq 1 40); do
  if sudo docker info >/dev/null 2>&1; then
    break
  fi
  echo "waiting for dockerd (${i}/40)" >&2
  sleep 0.25
done
if ! sudo docker info >/dev/null 2>&1; then
  echo "dockerd did not become ready after waiting" >&2
  exit 1
fi
sudo chmod 666 /var/run/docker.sock

# install.sh runs `just setup --skip-services` while the snapshot is built.
# Run `just setup` here on container start once dockerd is ready.
# Do not set OP_INTEGRATION_DISABLED here — that flag is install-process-only.
sudo -n -u ubuntu -H env MISE_ENV=dev,extras bash -euo pipefail -c '
  cd "$1"

  if [ -f .envrc ]; then
    echo "Trusting .envrc in $PWD"
    direnv allow .
  fi

  # linux-devbox installs just globally. Require just in the project mise config
  # so a global install does not run every project `setup` recipe.
  project_declares_just=false
  for mise_cfg in mise.toml .mise.toml .config/mise.toml; do
    if [ -f "$mise_cfg" ] && grep -Eq '^[[:space:]]*"?just"?[[:space:]]*=' "$mise_cfg"; then
      project_declares_just=true
      break
    fi
  done

  if [ -f justfile ] || [ -f Justfile ] || [ -f .justfile ]; then
    if [ "$project_declares_just" != true ]; then
      echo "justfile found in $PWD but just is not declared in the project mise config; skipping just setup"
    elif ! mise which just >/dev/null 2>&1; then
      echo "justfile found in $PWD but just is not installed via mise; skipping just setup"
    elif mise exec -- just --usage setup >/dev/null 2>&1; then
      echo "Running just setup in $PWD"
      mise exec -- direnv exec . just setup
    else
      echo "justfile found in $PWD but no setup recipe; skipping"
    fi
  fi
' bash "$PWD"
