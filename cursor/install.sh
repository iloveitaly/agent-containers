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

# rsync is required by iloveitaly/dotfiles install/linux-devbox.sh, which
# syncs the home directory before its own apt install.
for cmd in zsh direnv git rsync; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    packages+=("$cmd")
  fi
done

# NSS cert tools (certutil). Not on Cursor's default image; required by
# localias (and mkcert / Chromium NSS trust-store workflows).
if ! command -v certutil >/dev/null 2>&1; then
  packages+=(libnss3-tools)
fi

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

# Drop user-level copies from older installs so they cannot override /etc/mise
# during the system mise install below. A later linux-devbox rsync installs the
# dotfiles ~/.config/mise/config.toml; keep that file when this ref was already
# synced so a second install.sh does not wipe it.
dotfiles_ref="${DOTFILES_REF:-master}"
dotfiles_stamp=/var/lib/agent-containers/dotfiles-ref
if [ "$(cat "$dotfiles_stamp" 2>/dev/null || true)" != "$dotfiles_ref" ]; then
  rm -f "$HOME/.config/mise/config.toml" "$HOME/.config/mise/miserc.toml"
else
  rm -f "$HOME/.config/mise/miserc.toml"
fi

mkdir -p "$HOME/.config/direnv" "$HOME/.local/state/mise" "$HOME/.local/share/mise"
cat > "$HOME/.config/direnv/direnv.toml" <<'EOF'
[whitelist]
prefix = ["/workspace"]
EOF
touch "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.zshenv"
chmod 0644 "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.zshenv"
chown -R ubuntu:ubuntu "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.zshenv" "$HOME/.config" "$HOME/.local"

# System zshenv snippet: local file when present (image build, mounted tests),
# otherwise the copy published next to install.sh on master (curl | bash).
zshenv_snippet=/etc/zsh/agent-containers.zshenv
if [[ -f "$(dirname "$0")/snippets/zshenv" ]]; then
  install -m 0644 "$(dirname "$0")/snippets/zshenv" "$zshenv_snippet"
elif [[ -f /tmp/snippets/zshenv ]]; then
  install -m 0644 /tmp/snippets/zshenv "$zshenv_snippet"
else
  curl --retry 3 --retry-delay 5 -fsSL \
    https://raw.githubusercontent.com/iloveitaly/agent-containers/master/cursor/snippets/zshenv \
    -o "$zshenv_snippet"
  chmod 0644 "$zshenv_snippet"
fi

# lineinfile (via mise exec as ubuntu) edits these; keep root:ubuntu like /etc/mise.
touch /etc/zsh/zshenv /etc/environment
chown root:ubuntu /etc/zsh/zshenv /etc/environment
chmod 0664 /etc/zsh/zshenv /etc/environment

########################################################
# UBUNTU TOOLS & OPTIONAL PROJECT `just setup`
########################################################
# Mise install/exec must never run as root: tools land under ubuntu's
# ~/.local/share/mise, and root mise exec leaves root-owned files there
# (and can auto-install as uid 0). All mise install + mise exec (including
# lineinfile rc edits) run in this ubuntu subshell.
#
# python-starter-template's setup starts docker compose (`docker_up`) and
# seeds the DB. This script runs while the snapshot is built, before
# dockerd. `--skip-services` omits those steps. `start.sh` runs `just setup`
# on container start. Probe `just --usage setup` so a recipe without that
# flag still runs as `just setup`.
#
# OP_INTEGRATION_DISABLED is install-process-only (not in start.sh).

# bash -s: remaining args are $1.. (not $0). Heredoc is the script body.
sudo -n -u ubuntu -H env OP_INTEGRATION_DISABLED=1 MISE_ENV=dev,extras \
  bash -euo pipefail -s "$PWD" "$zshenv_snippet" <<'UBUNTU_SETUP'
cd "$1"
zshenv_snippet="$2"

if [ "$(id -u)" -eq 0 ]; then
  echo "mise install must not run as root" >&2
  exit 1
fi

# Shared NSS DB for Chromium / localias (certutil from libnss3-tools).
# The package does not create this; without it, trust-store installs fail.
mkdir -p "$HOME/.pki/nssdb"
if [ ! -f "$HOME/.pki/nssdb/cert9.db" ]; then
  certutil -d "sql:$HOME/.pki/nssdb" -N --empty-password
fi

if [ -f .envrc ]; then
  echo "Trusting .envrc in $PWD"
  direnv allow .
fi

# Lock + install system/global tools (lockfile: /etc/mise/mise.lock), plus
# project tools when a project mise config is present.
# Global tools include uv + lineinfile (gh if declared); pypi needs uv.
mise lock -g --platform linux-x64,linux-arm64
mise install

mise exec -- lineinfile add --create \
  --line "source ${zshenv_snippet}" \
  --regexp 'agent-containers\.zshenv' \
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

# Extensions install into $HOME/.local/share/gh/extensions.
# Do not use `gh extension list`: unauthenticated gh exits nonzero.
gh_ai_pr_dir="$HOME/.local/share/gh/extensions/gh-ai-pr"
if [ ! -d "$gh_ai_pr_dir" ]; then
  mise exec -- gh extension install iloveitaly/gh-ai-pr
fi

# linux-devbox installs just globally. That must not run every project
# `setup` recipe. Require just in the project mise config.
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
UBUNTU_SETUP

########################################################
# DOTFILES (iloveitaly/dotfiles install/linux-devbox.sh)
########################################################
# Mise is already at /usr/local/bin/mise. MISE_ENV and /workspace trust stay
# in /etc/mise and /etc/zsh/zshenv, which this rsync does not touch.
# Do not install another mise, and do not write ~/.config/mise/miserc.toml.
#
# linux-devbox.sh runs `mise self-update` and `zsh -lc` as ubuntu. The mise
# binary must be writable by ubuntu. TERM=dumb (and CURSOR_AGENT, which sudo
# would keep only with -E) makes .zshrc return before zinit loads, and the
# script's `set -e` then fails `zinit update`. Force a real TERM and do not
# pass -E. Forward a GitHub token when one is in this environment; Cursor
# agents already satisfy `mise token github` via ~/.config/gh/hosts.yml.
#
# install/mise/linux.toml sets libc=musl. On this glibc image that makes
# node and python fail to exec, and ast-grep has no musl asset, so
# `mise install` exits 1. MISE_LIBC=gnu overrides that setting here.

if [ "$(cat "$dotfiles_stamp" 2>/dev/null || true)" != "$dotfiles_ref" ]; then
  rm -rf /opt/dotfiles
  git clone --depth 1 --branch "$dotfiles_ref" https://github.com/iloveitaly/dotfiles.git /opt/dotfiles
  chown -R ubuntu:ubuntu /opt/dotfiles
  if ! sudo -n -u ubuntu test -w /usr/local/bin/mise; then
    chown ubuntu:ubuntu /usr/local/bin/mise
  fi
  dotfiles_env=(TERM=xterm-256color MISE_LIBC=gnu)
  if [ -n "${MISE_GITHUB_TOKEN:-}" ]; then
    dotfiles_env+=(MISE_GITHUB_TOKEN="$MISE_GITHUB_TOKEN")
  elif [ -n "${GITHUB_TOKEN:-}" ]; then
    dotfiles_env+=(MISE_GITHUB_TOKEN="$GITHUB_TOKEN")
  fi
  sudo -n -u ubuntu -H env "${dotfiles_env[@]}" bash /opt/dotfiles/install/linux-devbox.sh
  mkdir -p /var/lib/agent-containers
  printf '%s\n' "$dotfiles_ref" > "$dotfiles_stamp"
fi

# The rsync replaces ~/.config/direnv/direnv.toml with the dotfiles file
# (strict_env, warn_timeout, no whitelist). Put /workspace back.
direnv_toml="$HOME/.config/direnv/direnv.toml"
mkdir -p "$(dirname "$direnv_toml")"
if [ ! -f "$direnv_toml" ]; then
  printf '%s\n' '[whitelist]' 'prefix = ["/workspace"]' > "$direnv_toml"
elif ! grep -q '/workspace' "$direnv_toml"; then
  printf '\n%s\n' '[whitelist]' 'prefix = ["/workspace"]' >> "$direnv_toml"
fi
chown ubuntu:ubuntu "$direnv_toml"
