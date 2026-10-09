#!/usr/bin/env bash
set -euo pipefail

# Cursor Cloud `install` runs as ubuntu (passwordless sudo). Docker image
# builds and "fresh Ubuntu host" runs are already root. Re-exec so apt/gpg
# can write /etc/apt/keyrings and the rest of this script can run as root.
if [ "$(id -u)" -ne 0 ]; then
  if ! sudo -n true 2>/dev/null; then
    echo "install.sh must run as root or with passwordless sudo" >&2
    exit 1
  fi
  # `curl | bash` feeds the script on stdin ($0 is bash /usr/bin/bash).
  # `bash cursor/install.sh` has a real script path in $0.
  case "$0" in
    bash|sh|-|*/bash|*/sh)
      exec sudo -n -E bash -s "$@"
      ;;
    *)
      exec sudo -n -E bash "$0" "$@"
      ;;
  esac
fi

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
need_direnv=false

########################################################
# DOCKER APT SOURCE
########################################################

if ! command -v docker >/dev/null 2>&1; then
  need_docker=true
  install -m 0755 -d /etc/apt/keyrings /root/.gnupg
  chmod 700 /root/.gnupg
  # --batch/--yes: overwrite without prompting (no /dev/tty in Cloud Agent install).
  # GNUPGHOME under /root avoids "unsafe ownership" when HOME is still ubuntu's.
  curl --retry 3 --retry-delay 5 -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --homedir /root/.gnupg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  packages+=(
    docker-ce=5:28.5.2-1~ubuntu.24.04~noble
    docker-ce-cli=5:28.5.2-1~ubuntu.24.04~noble
    containerd.io
    docker-buildx-plugin
    docker-compose-plugin
    fuse-overlayfs
    iptables
  )
fi

if ! command -v zsh >/dev/null 2>&1; then
  packages+=(zsh)
fi

if ! command -v direnv >/dev/null 2>&1; then
  need_direnv=true
  packages+=(direnv)
fi

if ! command -v git >/dev/null 2>&1; then
  packages+=(git)
fi

if ((${#packages[@]})); then
  apt-get update
  # Acquire::Retries covers dropped connections, not HTTP 400 from
  # archive.ubuntu.com/Cloudflare. Retry the install only — lists stay cached.
  attempt=1
  until apt-get install -y -- "${packages[@]}"; do
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
chsh -s /bin/zsh ubuntu
# Create docker group if it doesn't exist and add ubuntu user to it
groupadd -f docker && usermod -aG docker ubuntu
usermod -aG sudo ubuntu
# Configure passwordless sudo for ubuntu user
echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu
# Set a password for ubuntu user
echo "ubuntu:ubuntu" | chpasswd

# This script stays root so it can apt-install and write /etc. Mise, direnv's
# allow database, and gh extensions belong to ubuntu.
# -H sets HOME to that user. -n fails instead of prompting if sudo needs a password.
as_ubuntu() {
  sudo -n -u ubuntu -H "$@"
}

# Run a command as ubuntu after cd'ing to the project root.
# That is the directory install.sh was started in ($PWD): Cursor's /workspace,
# or wherever `curl | bash` was run. sudo does not promise to keep that cwd.
as_ubuntu_in_project() {
  as_ubuntu bash -c 'cd "$1" && shift && exec "$@"' bash "$PWD" "$@"
}

# Run a command as ubuntu in the project root, with mise applied and then
# .envrc. `direnv exec` applies .envrc to the command. The shell hook is
# `eval "$(direnv export bash)"` because a child process cannot change the
# parent shell's environment; there is no other way to load that diff here.
with_mise_and_direnv() {
  as_ubuntu bash -c '
    set -euo pipefail
    cd "$1" || exit 1
    shift
    mise_activate="$(mise activate bash)"
    eval "$mise_activate"
    if [ -f .envrc ]; then
      exec direnv exec . "$@"
    fi
    exec "$@"
  ' bash "$PWD" "$@"
}

# Script runs as root during image build; point HOME at the ubuntu user.
export HOME="$(getent passwd ubuntu | cut -d: -f6)"
touch "$HOME/.bashrc" "$HOME/.zshrc"

########################################################
# MISE INSTALL
########################################################
# Load order guide (iloveitaly/dotfiles .zsh_plugins):
#   wait'0a' — PATH/tooling needed ASAP (mise)
# Shell hook must run before direnv.

# MISE_ENV selects mise.<env>.toml (including .config/mise.<env>.toml).
# dev,extras is tied to the assumed config of
# https://github.com/iloveitaly/python-starter-template/
# (.config/mise.dev.toml and .config/mise.extras.toml).
# Exported for ubuntu shells, and written to ~/.config/mise/miserc.toml so
# non-interactive mise (agent commands, `as_ubuntu`) loads the same
# files. MISE_ENV cannot live in mise config.toml; that file is read too late.
export MISE_ENV=dev,extras
mise_env_snippet=$(cat <<'EOF'
# MISE_ENV=dev,extras is tied to the assumed config of
# https://github.com/iloveitaly/python-starter-template/
# (.config/mise.dev.toml and .config/mise.extras.toml).
export MISE_ENV=dev,extras
EOF
)
for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.zshenv"; do
  touch "$rc"
  if ! grep -qxF 'export MISE_ENV=dev,extras' "$rc"; then
    tmp="$(mktemp)"
    printf '%s\n' "$mise_env_snippet" | cat - "$rc" > "$tmp"
    mv "$tmp" "$rc"
  fi
done

# Install mise only if the mise CLI is not already present
if ! command -v mise >/dev/null 2>&1; then
  curl --retry 3 --retry-delay 5 -fsSL https://mise.run | MISE_INSTALL_MUSL=1 MISE_INSTALL_PATH=/usr/local/bin/mise sh
  # Activate mise for interactive shells (bash + zsh). mise first, matching wait'0a'.
  touch "$HOME/.bashrc" "$HOME/.zshrc"
  cat >> "$HOME/.bashrc" <<'EOF'
eval "$(mise activate bash)"
EOF
  cat >> "$HOME/.zshrc" <<'EOF'
eval "$(mise activate zsh)"
EOF
fi
# Cursor cloud agents mount the repo at /workspace — trust configs there without prompts.
# Cloud images often already have `gh`; only add it to mise when missing.
mkdir -p "$HOME/.config/mise"
{
  cat <<'EOF'
[settings]
trusted_config_paths = ["/workspace"]

[tools]
uv = "latest"
EOF
  if ! command -v gh >/dev/null 2>&1; then
    echo 'gh = "latest"'
  fi
} > "$HOME/.config/mise/config.toml"
# Same dev,extras selection as the shell export above. miserc is read before
# project config, which is what makes MISE_ENV apply to every mise invocation.
cat > "$HOME/.config/mise/miserc.toml" <<'EOF'
# Tied to the assumed config of
# https://github.com/iloveitaly/python-starter-template/
# (.config/mise.dev.toml and .config/mise.extras.toml).
env = ["dev", "extras"]
EOF
chown -R ubuntu:ubuntu "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.zshenv" "$HOME/.config"

########################################################
# DIRENV HOOKS
########################################################
# Load order guide (iloveitaly/dotfiles .zsh_plugins):
#   wait'0b' — after mise (see 0b/direnv.zsh)
# Hook must run after mise so direnv inherits the mise-managed PATH.

if $need_direnv; then
  # Activate direnv after mise (bash + zsh), matching 0b/direnv.zsh.
  touch "$HOME/.bashrc" "$HOME/.zshrc"
  cat >> "$HOME/.bashrc" <<'EOF'
eval "$(direnv hook bash)"
EOF
  cat >> "$HOME/.zshrc" <<'EOF'
eval "$(direnv hook zsh)"
EOF
fi
# Whitelist /workspace so .envrc loads without `direnv allow` on first shell.
mkdir -p "$HOME/.config/direnv"
cat > "$HOME/.config/direnv/direnv.toml" <<'EOF'
[whitelist]
prefix = ["/workspace"]
EOF
chown -R ubuntu:ubuntu "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.zshenv" "$HOME/.config"

# Trust the project .envrc now that direnv is installed. The `/workspace`
# whitelist covers Cursor Cloud; `direnv allow` also trusts an install root
# outside that prefix. Allow does not execute the file. `with_mise_and_direnv`
# does, via `direnv exec`, when it runs `just setup`.
if [ -f .envrc ]; then
  echo "Trusting .envrc in $PWD"
  # Record trust only. .envrc runs later, inside with_mise_and_direnv.
  as_ubuntu_in_project direnv allow .
fi

########################################################
# GLOBAL MISE TOOLS
########################################################
# Tools from ~/.config/mise/config.toml (`mise use -g`).
# gh-ai-pr is a uv inline script (`#!/usr/bin/env -S uv run --script`).

# Install global mise tools, plus project tools when a project mise config is present.
as_ubuntu_in_project mise install

########################################################
# GH AI-PR EXTENSION
########################################################
# Extensions install into $HOME/.local/share/gh/extensions. The agent
# session runs as ubuntu, so install as that user (not root).
# Prefer an already-installed gh; otherwise `mise exec` puts mise gh on PATH.
# Do not use `gh extension list` here: unauthenticated gh (Docker image
# builds, fresh hosts) exits with "please run: gh auth login".

gh_ai_pr_dir="$(getent passwd ubuntu | cut -d: -f6)/.local/share/gh/extensions/gh-ai-pr"
if [ ! -d "$gh_ai_pr_dir" ]; then
  if command -v gh >/dev/null 2>&1; then
    as_ubuntu gh extension install iloveitaly/gh-ai-pr
  else
    as_ubuntu mise exec -- gh extension install iloveitaly/gh-ai-pr
  fi
fi

########################################################
# OPTIONAL PROJECT `just setup`
########################################################
# `install` runs from the app root (Cursor Cloud and curl|bash). Docker image
# builds have no project justfile in $PWD, so this is a no-op there.
# Do not install just ourselves: projects that need it put it in mise.
#
# `with_mise_and_direnv` activates mise, then `direnv exec` when .envrc
# exists, then runs the recipe. `mise exec -- just setup` would skip .envrc.

if [ -f justfile ] || [ -f Justfile ] || [ -f .justfile ]; then
  # just is a project tool. Skip setup when this project does not install it.
  if as_ubuntu_in_project mise which just >/dev/null 2>&1; then
    # Confirm the justfile defines a setup recipe before running it.
    if as_ubuntu_in_project mise exec -- just --show setup >/dev/null 2>&1; then
      echo "Running just setup in $PWD"
      # mise hook-env, then .envrc, then the recipe.
      with_mise_and_direnv just setup
    else
      echo "justfile found in $PWD but no setup recipe; skipping"
    fi
  else
    echo "justfile found in $PWD but just is not installed via mise; skipping just setup"
  fi
fi
