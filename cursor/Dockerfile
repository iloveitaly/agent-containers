FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Cursor-like base: hosted Cloud Agents already have these; this image is the
# stand-in when we are not on Cursor's unpublished VM (GHCR / local just).
# Do not put these in install.sh — that script is the overlay (Docker, mise,
# direnv, zsh) and runs via curl|bash on top of Cursor's own image.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    sudo \
    locales \
    xz-utils \
    tmux \
    python3 \
    jq \
    ripgrep \
    unzip \
    && locale-gen en_US.UTF-8 \
    && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

COPY install.sh /tmp/install.sh
COPY snippets/zshenv /tmp/snippets/zshenv
# linux-devbox.sh requires a GitHub token when gh is not already logged in.
# Pass it as a BuildKit secret so it is not stored in the image:
#   docker build --secret id=github_token,env=MISE_GITHUB_TOKEN ...
# Cursor Cloud already has ~/.config/gh/hosts.yml, so the secret is optional.
RUN --mount=type=secret,id=github_token,required=false \
    bash -c 'if [ -s /run/secrets/github_token ]; then export MISE_GITHUB_TOKEN="$(cat /run/secrets/github_token)"; fi; bash /tmp/install.sh' \
    && rm -rf /tmp/install.sh /tmp/snippets

USER ubuntu
WORKDIR /home/ubuntu
