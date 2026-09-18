FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Cursor-like base: hosted Cloud Agents already have these; this image is the
# stand-in when we are not on Cursor's unpublished VM (GHCR / local just).
# Do not put these in install.sh — that script is the overlay (Docker, mise,
# direnv, zsh) and runs via curl|bash on top of Cursor's own image.
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
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
RUN bash /tmp/install.sh && rm /tmp/install.sh
