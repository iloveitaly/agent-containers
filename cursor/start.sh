#!/usr/bin/env bash
set -euo pipefail

# Cursor expects long-lived services in `start`, not `install`.
# See https://cursor.com/docs/cloud-agent/setup#running-docker
sudo service docker start

# usermod -aG docker from install.sh does not apply until a new login;
# open the socket so the current agent session can use docker without
# newgrp / sg. Fine for ephemeral agent VMs.
sudo chmod 666 /var/run/docker.sock
