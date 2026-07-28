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
  printf '%s\n' '{' \
    '  "storage-driver": "fuse-overlayfs"' \
    '}' > /etc/docker/daemon.json
  apt-get update && apt-get install -y iptables && rm -rf /var/lib/apt/lists/*
  update-alternatives --set iptables /usr/sbin/iptables-legacy
  update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
fi

########################################################
# CONFIG UBUNTU USER
########################################################

# ensure no password authentication
mkdir -p /etc/ssh/sshd_config.d
echo 'PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM no' > /etc/ssh/sshd_config.d/disable_password_auth.conf

# Create non-root user (only if it doesn't exist)
id -u ubuntu &>/dev/null || useradd -m -s /bin/bash ubuntu
# Create docker group if it doesn't exist and add ubuntu user to it
groupadd -f docker && usermod -aG docker ubuntu
usermod -aG sudo ubuntu
# Configure passwordless sudo for ubuntu user
echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu
# Set a password for ubuntu user
echo "ubuntu:ubuntu" | chpasswd

# Script runs as root during image build; point HOME at the ubuntu user.
export HOME="$(getent passwd ubuntu | cut -d: -f6)"

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
  printf '%s\n' 'eval "$(mise activate bash)"' >> "$HOME/.bashrc"
  printf '%s\n' 'eval "$(mise activate zsh)"' >> "$HOME/.zshrc"
  chown ubuntu:ubuntu "$HOME/.bashrc" "$HOME/.zshrc"
fi

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
  printf '%s\n' 'eval "$(direnv hook bash)"' >> "$HOME/.bashrc"
  printf '%s\n' 'eval "$(direnv hook zsh)"' >> "$HOME/.zshrc"
  chown ubuntu:ubuntu "$HOME/.bashrc" "$HOME/.zshrc"
fi
