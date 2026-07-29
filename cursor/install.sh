#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

########################################################
# DOCKER INSTALLATION
########################################################

# Install Docker only if the docker CLI is not already present
if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl --retry 3 --retry-delay 5 -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt-get update
  apt-get install -y \
    docker-ce=5:28.5.2-1~ubuntu.24.04~noble \
    docker-ce-cli=5:28.5.2-1~ubuntu.24.04~noble \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
  rm -rf /var/lib/apt/lists/*

  apt-get update && apt-get install -y fuse-overlayfs && rm -rf /var/lib/apt/lists/*
  mkdir -p /etc/docker
  cat > /etc/docker/daemon.json <<'EOF'
{
  "storage-driver": "fuse-overlayfs"
}
EOF
  apt-get update && apt-get install -y iptables && rm -rf /var/lib/apt/lists/*
  update-alternatives --set iptables /usr/sbin/iptables-legacy
  update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
fi

########################################################
# CONFIG UBUNTU USER
########################################################

# Justfile and agent shells expect zsh; install it before creating/updating the user.
if ! command -v zsh >/dev/null 2>&1; then
  apt-get update && apt-get install -y zsh && rm -rf /var/lib/apt/lists/*
fi

# ensure no password authentication
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/disable_password_auth.conf <<'EOF'
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM no
EOF

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

# Script runs as root during image build; point HOME at the ubuntu user.
export HOME="$(getent passwd ubuntu | cut -d: -f6)"
touch "$HOME/.bashrc" "$HOME/.zshrc"

########################################################
# MISE INSTALL
########################################################
# Load order guide (iloveitaly/dotfiles .zsh_plugins):
#   wait'0a' — PATH/tooling needed ASAP (mise)
# Shell hook must run before direnv.

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
mkdir -p "$HOME/.config/mise"
cat > "$HOME/.config/mise/config.toml" <<'EOF'
[settings]
trusted_config_paths = ["/workspace"]
EOF
chown -R ubuntu:ubuntu "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.config"

########################################################
# DIRENV INSTALL
########################################################
# Load order guide (iloveitaly/dotfiles .zsh_plugins):
#   wait'0b' — after mise (see 0b/direnv.zsh)
# Hook must run after mise so direnv inherits the mise-managed PATH.

# Install direnv only if the direnv CLI is not already present
if ! command -v direnv >/dev/null 2>&1; then
  apt-get update && apt-get install -y direnv && rm -rf /var/lib/apt/lists/*
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
chown -R ubuntu:ubuntu "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.config"
