#!/usr/bin/env bash
set -euo pipefail

# Cursor expects long-lived services in `start`, not `install`.
# See https://cursor.com/docs/cloud-agent/setup#running-docker
#
# `install.sh` runs while the environment snapshot is built. It runs
# `just setup --skip-services` there, because dockerd is not up yet and
# processes from that build are not kept. This script runs on every
# container start. After the daemon is up, run the project's full
# `just setup` so compose and DB seed happen in the running container.
#
# Headless sessions have no 1Password app. Set this before direnv, mise,
# or just can talk to `op`. `sudo -u` below drops the environment, so the
# ubuntu command sets it again.
export OP_INTEGRATION_DISABLED=1

# Tests pass --skip-docker to exercise project setup without a daemon.
# Cursor's start command is `curl | bash` and passes no arguments.
skip_docker=0
if [ "${1:-}" = "--skip-docker" ]; then
  skip_docker=1
fi

if [ "$skip_docker" -eq 0 ]; then
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
fi

# Same ubuntu + mise + direnv path as install.sh. Duplicated here because
# Cursor fetches install.sh and start.sh separately with `curl | bash`.
as_ubuntu() {
  sudo -n -u ubuntu -H env OP_INTEGRATION_DISABLED=1 "$@"
}

# Run a command as ubuntu after cd'ing to the directory start.sh was
# started in ($PWD). Cursor's start runs from the app root. sudo does not
# promise to keep that cwd.
as_ubuntu_in_project() {
  as_ubuntu bash -c 'cd "$1" && shift && exec "$@"' bash "$PWD" "$@"
}

# Activate mise, then `direnv exec` when .envrc exists, then run the
# command. `mise exec -- just setup` would skip .envrc.
with_mise_and_direnv() {
  as_ubuntu bash -c '
    set -euo pipefail
    cd "$1" || exit 1
    shift
    mise_activate="$(mise activate bash)"
    eval "$mise_activate"
    # Set again after mise activate, before .envrc and the recipe. direnv
    # keeps variables already in the environment unless .envrc unsets them.
    export OP_INTEGRATION_DISABLED=1
    if [ -f .envrc ]; then
      exec direnv exec . "$@"
    fi
    exec "$@"
  ' bash "$PWD" "$@"
}

# Trust .envrc for this checkout. The snapshot's allow list is the default
# branch; the agent may have checked out a different revision. Allow does
# not execute the file. `with_mise_and_direnv` does, via `direnv exec`.
if [ -f .envrc ]; then
  echo "Trusting .envrc in $PWD"
  as_ubuntu_in_project direnv allow .
fi

# Full `just setup` (compose and DB seed included). install.sh already ran
# the `--skip-services` form into the snapshot when the recipe supports it.
# Do not install just: projects that need it put it in mise.
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
