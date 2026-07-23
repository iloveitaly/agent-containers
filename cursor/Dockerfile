FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    sudo \
    && rm -rf /var/lib/apt/lists/*

COPY install.sh /tmp/install.sh
RUN bash /tmp/install.sh && rm /tmp/install.sh
