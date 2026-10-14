#!/usr/bin/env bash
set -euo pipefail

# Headless installs have no 1Password desktop app. `op` (from a just recipe,
# a .envrc, or a mise hook) otherwise waits on that app. Set this only for the
# install process — do not persist it into shell rc, /etc/environment, or start.
export OP_INTEGRATION_DISABLED=1

# Cursor Cloud `install` runs as ubuntu (passwordless sudo). Docker image
# builds and "fresh Ubuntu host" runs are already root. Re-exec so apt can
# write /etc/apt/keyrings and the rest of this script can run as root.
if [ "$(id -u)" -ne 0 ]; then
  if ! sudo -n true 2>/dev/null; then
    echo "install.sh must run as root or with passwordless sudo" >&2
    exit 1
  fi
  # `curl | bash` feeds the script on stdin ($0 is bash /usr/bin/bash).
  # Pass -euo pipefail explicitly because the outer shell already consumed the
  # header lines from stdin before exec'ing into root bash.
  case "$0" in
    bash|sh|-|*/bash|*/sh)
      exec sudo -n -E bash -euo pipefail -s "$@"
      ;;
    *)
      exec sudo -n -E bash -euo pipefail "$0" "$@"
      ;;
  esac
fi

export OP_INTEGRATION_DISABLED=1
export DEBIAN_FRONTEND=noninteractive

# Written to /etc/apt so later apt-get in this script picks it up.
cat > /etc/apt/apt.conf.d/99-install-retries <<'EOF'
// Retry a fetch that dropped or got HTTP 5xx. Does not retry HTTP 400.
Acquire::Retries "5";
// Give up on a hung HTTP fetch after 30s instead of hanging the install.
Acquire::http::Timeout "30";
// Cloud images already have /etc/fuse.conf. Keep it; never prompt.
Dpkg::Options { "--force-confdef"; "--force-confold"; };
EOF

packages=()
need_docker=false

########################################################
# DOCKER APT SOURCE
########################################################

if ! command -v docker >/dev/null 2>&1; then
  need_docker=true
  install -m 0755 -d /etc/apt/keyrings
  curl --retry 3 --retry-delay 5 -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${codename} stable" \
    > /etc/apt/sources.list.d/docker.list
  packages+=(
    "docker-ce=5:28.5.2-1~ubuntu.24.04~${codename}"
    "docker-ce-cli=5:28.5.2-1~ubuntu.24.04~${codename}"
    containerd.io
    docker-buildx-plugin
    docker-compose-plugin
    fuse-overlayfs
    iptables
  )
fi

for cmd in zsh direnv git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    packages+=("$cmd")
  fi
done

if ((${#packages[@]})); then
  apt-get update
  # Acquire::Retries covers dropped connections, not HTTP 400 from
  # archive.ubuntu.com/Cloudflare. Retry the install only — lists stay cached.
  attempt=1
  until apt-get install -y --no-install-recommends -- "${packages[@]}"; do
    if ((attempt >= 5)); then
      echo "apt-get install failed after ${attempt} attempts: ${packages[*]}" >&2
      exit 1
    fi
    attempt=$((attempt + 1))
    sleep 2
  done
  rm -rf /var/lib/apt/lists/*
fi

########################################################
# DOCKER DAEMON CONFIG
########################################################

if $need_docker; then
  mkdir -p /etc/docker
  cat > /etc/docker/daemon.json <<'EOF'
{
  "storage-driver": "fuse-overlayfs"
}
EOF
  update-alternatives --set iptables /usr/sbin/iptables-legacy
  update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
fi

########################################################
# CONFIG UBUNTU USER
########################################################

# Create non-root user (only if it doesn't exist); default shell is zsh.
id -u ubuntu &>/dev/null || useradd -m -s /bin/zsh ubuntu
groupadd -f docker
usermod -s /bin/zsh -aG docker,sudo ubuntu
echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu

# Script runs as root; point HOME at the ubuntu user for rc/config writes.
export HOME="$(getent passwd ubuntu | cut -d: -f6)"

########################################################
# MISE & DIRENV CONFIG
########################################################
# Load order guide (iloveitaly/dotfiles .zsh_plugins):
#   wait'0a' — PATH/tooling needed ASAP (mise)
#   wait'0b' — after mise (direnv)
#
# Agent invariants live under /etc so a later home-directory rsync (dotfiles)
# does not clobber them:
#   /etc/zsh/zshenv          — every zsh (incl. non-interactive)
#   /etc/mise/miserc.toml    — MISE_ENV selection before project config
#   /etc/mise/config.toml    — trusted /workspace + global uv (gh if missing)
#   /etc/environment         — PAM / sudo sessions (MISE_ENV only)

# MISE_ENV selects mise.<env>.toml (including .config/mise.<env>.toml).
# Tied to the assumed config of
# https://github.com/iloveitaly/python-starter-template/
# (.config/mise.dev.toml and .config/mise.extras.toml).
export MISE_ENV=dev,extras

if ! command -v mise >/dev/null 2>&1; then
  curl --retry 3 --retry-delay 5 -fsSL https://mise.run | MISE_INSTALL_MUSL=1 MISE_INSTALL_PATH=/usr/local/bin/mise sh
fi

# System mise config (lowest precedence; survives ~/.config/mise rsync).
# Directory is root:ubuntu 775 so `mise lock -g` as ubuntu can write mise.lock.
# Write this before lineinfile: the pypi backend needs uv from this config.
mkdir -p /etc/mise
chown root:ubuntu /etc/mise
chmod 0775 /etc/mise
{
  cat <<'EOF'
[settings]
trusted_config_paths = ["/workspace"]

[tools]
# python: required for locked pypi:* graph installs (e.g. lineinfile)
python = "3"
uv = "latest"
"pypi:lineinfile" = "latest"
EOF
  if ! command -v gh >/dev/null 2>&1; then
    echo 'gh = "latest"'
  fi
} > /etc/mise/config.toml

# miserc is read before project config; env cannot live in config.toml.
cat > /etc/mise/miserc.toml <<'EOF'
# Tied to the assumed config of
# https://github.com/iloveitaly/python-starter-template/
# (.config/mise.dev.toml and .config/mise.extras.toml).
env = ["dev", "extras"]
EOF
chmod 0644 /etc/mise/config.toml /etc/mise/miserc.toml

# Drop user-level copies from older installs so they cannot override /etc/mise.
rm -f "$HOME/.config/mise/config.toml" "$HOME/.config/mise/miserc.toml"

mkdir -p "$HOME/.config/direnv" "$HOME/.local/state/mise" "$HOME/.local/share/mise"
cat > "$HOME/.config/direnv/direnv.toml" <<'EOF'
[whitelist]
prefix = ["/workspace"]
EOF
touch "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.zshenv"
chmod 0644 "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.zshenv"
chown -R ubuntu:ubuntu "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.zshenv" "$HOME/.config" "$HOME/.local"

# Global tools (uv + lineinfile; gh if declared). pypi backend needs uv.
sudo -n -u ubuntu -H env MISE_ENV=dev,extras mise install

# System zshenv: MISE_ENV + shims for all zsh invocations.
mise exec -- lineinfile add --create \
  --line 'export MISE_ENV=dev,extras' --regexp '^export MISE_ENV=' \
  /etc/zsh/zshenv
mise exec -- lineinfile add --create \
  --line 'eval "$(mise activate zsh --shims)"' --regexp 'mise activate zsh --shims' \
  /etc/zsh/zshenv

# PAM login and sudo sessions. Do not persist OP_INTEGRATION_DISABLED.
mise exec -- lineinfile add --create \
  --line 'MISE_ENV=dev,extras' --regexp '^MISE_ENV=' \
  /etc/environment
mise exec -- lineinfile remove \
  --regexp '^(export )?OP_INTEGRATION_DISABLED=' \
  /etc/environment

# Bash: stock ~/.bashrc returns early when non-interactive, so put MISE_ENV at BOF.
# Drop OP_INTEGRATION_DISABLED left by older installs (install-process-only).
mise exec -- lineinfile add --create --bof \
  --line 'export MISE_ENV=dev,extras' --regexp '^export MISE_ENV=' \
  "$HOME/.bashrc"
mise exec -- lineinfile remove \
  --regexp '^(export )?OP_INTEGRATION_DISABLED=' \
  "$HOME/.bashrc"
mise exec -- lineinfile remove \
  --regexp '^(export )?OP_INTEGRATION_DISABLED=' \
  "$HOME/.zshenv"

# Interactive shell hooks: mise first (wait'0a'), then direnv (wait'0b').
mise exec -- lineinfile add --create \
  --line 'eval "$(mise activate bash)"' --regexp 'mise activate bash' \
  "$HOME/.bashrc"
mise exec -- lineinfile add --create \
  --line 'eval "$(direnv hook bash)"' --regexp 'direnv hook bash' \
  "$HOME/.bashrc"
mise exec -- lineinfile add --create \
  --line 'eval "$(mise activate zsh)"' --regexp 'mise activate zsh' \
  "$HOME/.zshrc"
mise exec -- lineinfile add --create \
  --line 'eval "$(direnv hook zsh)"' --regexp 'direnv hook zsh' \
  "$HOME/.zshrc"

########################################################
# UBUNTU TOOLS & OPTIONAL PROJECT `just setup`
########################################################
# Mise, direnv's allow database, and gh extensions belong to ubuntu.
# Run the user-space setup in a single ubuntu subshell in the project root ($PWD).
#
# python-starter-template's setup starts docker compose (`docker_up`) and
# seeds the DB. This script runs while the snapshot is built, before
# dockerd. `--skip-services` omits those steps. `start.sh` runs `just setup`
# on container start. Probe `just --usage setup` so a recipe without that
# flag still runs as `just setup`.
#
# OP_INTEGRATION_DISABLED is install-process-only (not in start.sh).

sudo -n -u ubuntu -H env OP_INTEGRATION_DISABLED=1 MISE_ENV=dev,extras bash -euo pipefail -c '
  cd "$1"

  if [ -f .envrc ]; then
    echo "Trusting .envrc in $PWD"
    direnv allow .
  fi

  # Lock + install system/global tools (lockfile: /etc/mise/mise.lock), plus
  # project tools when a project mise config is present.
  mise lock -g --platform linux-x64,linux-arm64
  mise install

  # Extensions install into $HOME/.local/share/gh/extensions.
  # Do not use `gh extension list`: unauthenticated gh exits nonzero.
  gh_ai_pr_dir="$HOME/.local/share/gh/extensions/gh-ai-pr"
  if [ ! -d "$gh_ai_pr_dir" ]; then
    mise exec -- gh extension install iloveitaly/gh-ai-pr
  fi

  if [ -f justfile ] || [ -f Justfile ] || [ -f .justfile ]; then
    if ! mise which just >/dev/null 2>&1; then
      echo "justfile found in $PWD but just is not installed via mise; skipping just setup"
    elif usage="$(mise exec -- just --usage setup 2>/dev/null)"; then
      setup_cmd=(just setup)
      if grep -q -- "--skip-services" <<<"$usage"; then
        setup_cmd+=(--skip-services)
      fi
      echo "Running ${setup_cmd[*]} in $PWD"
      mise exec -- direnv exec . "${setup_cmd[@]}"
    else
      echo "justfile found in $PWD but no setup recipe; skipping"
    fi
  fi
' bash "$PWD"
