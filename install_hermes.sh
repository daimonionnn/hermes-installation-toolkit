#!/usr/bin/env bash
# install_hermes.sh
#
# Runs the official Hermes Agent installer as the current user.
#
# Do not run with sudo: the rest of this toolkit assumes a per-user install
# in ~/.hermes with a systemd --user gateway. Under root the installer switches
# to a system layout (/usr/local/lib/hermes-agent, data in /root/.hermes).
# The installer asks for sudo on its own when it needs system packages.
#
# Usage:  bash install_hermes.sh

set -euo pipefail

if [[ $EUID -eq 0 ]]; then
    echo "ERROR: run as your normal user, not root (this toolkit expects ~/.hermes)." >&2
    exit 1
fi

curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
