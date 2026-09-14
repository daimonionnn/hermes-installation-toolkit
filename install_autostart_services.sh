#!/usr/bin/env bash
# install_autostart_services.sh
#
# Creates and enables two systemd services that start at boot (no login required):
#   firecrawl.service  – Firecrawl Docker stack      → http://localhost:3002
#   chrome-cdp.service – Chrome remote debugging CDP → http://localhost:9222
#
# NOTE: The native Hermes gateway is already managed by its own user service
#       installed via "hermes gateway install". No need to duplicate it here.
#
# Usage:  sudo ./install_autostart_services.sh
#         sudo SERVICE_USER=alice ./install_autostart_services.sh   # explicit user

set -euo pipefail

# ── Require root ──────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: run with sudo:  sudo $0" >&2
    exit 1
fi

# ── Resolve the calling user (not root) ───────────────────────────────────────
SERVICE_USER="${SERVICE_USER:-${SUDO_USER:-}}"
if [[ -z "$SERVICE_USER" || "$SERVICE_USER" == "root" ]]; then
    echo "ERROR: could not determine the non-root user to run the services as." >&2
    echo "       Run via sudo from that user's shell, or set SERVICE_USER=<name>." >&2
    exit 1
fi
if ! getent passwd "$SERVICE_USER" >/dev/null; then
    echo "ERROR: user '$SERVICE_USER' does not exist." >&2
    exit 1
fi
USER_HOME=$(getent passwd "$SERVICE_USER" | cut -d: -f6)
USER_UID=$(id -u "$SERVICE_USER")
USER_GID=$(id -g "$SERVICE_USER")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER="/usr/bin/docker"
FIRECRAWL_DIR="$USER_HOME/firecrawl"
CHROME_DATA_DIR="$USER_HOME/.config/google-chrome-ai-agent"

echo "==> Installing autostart services for user: $SERVICE_USER (UID=$USER_UID GID=$USER_GID)"
echo "    Toolkit dir : $SCRIPT_DIR"
echo "    Firecrawl   : $FIRECRAWL_DIR"
echo ""

# ── Sanity checks ─────────────────────────────────────────────────────────────
[[ -d "$FIRECRAWL_DIR" ]] || { echo "ERROR: $FIRECRAWL_DIR not found"; exit 1; }
[[ -x "$DOCKER" ]]        || { echo "ERROR: $DOCKER not found or not executable"; exit 1; }

CHROME_BIN=$(command -v google-chrome || command -v google-chrome-stable || true)
[[ -n "$CHROME_BIN" ]] || { echo "ERROR: google-chrome not found in PATH"; exit 1; }

# ── 1. firecrawl.service ──────────────────────────────────────────────────────
echo "==> Writing /etc/systemd/system/firecrawl.service"
cat > /etc/systemd/system/firecrawl.service <<EOF
[Unit]
Description=Firecrawl Docker Stack
Documentation=https://github.com/firecrawl/firecrawl
After=docker.service network-online.target
Wants=network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=$SERVICE_USER
Group=docker
WorkingDirectory=$FIRECRAWL_DIR
EnvironmentFile=-$FIRECRAWL_DIR/.env
ExecStart=$DOCKER compose up -d --remove-orphans
ExecStop=$DOCKER compose down
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
EOF

# ── 2. chrome-cdp.service ────────────────────────────────────────────────────
echo "==> Writing /etc/systemd/system/chrome-cdp.service"
cat > /etc/systemd/system/chrome-cdp.service <<EOF
[Unit]
Description=Google Chrome CDP Remote Debugging (port 9222)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
Restart=on-failure
RestartSec=5
ExecStart=$CHROME_BIN \\
    --remote-debugging-port=9222 \\
    --user-data-dir=$CHROME_DATA_DIR \\
    --headless=new \\
    --no-sandbox \\
    --disable-gpu \\
    --disable-dev-shm-usage \\
    --disable-extensions \\
    --no-first-run \\
    --no-default-browser-check
KillMode=control-group

[Install]
WantedBy=multi-user.target
EOF

# ── Reload, enable, start ─────────────────────────────────────────────────────
echo ""
echo "==> Reloading systemd and enabling services..."
systemctl daemon-reload
systemctl enable firecrawl.service chrome-cdp.service

echo "==> Starting services..."
systemctl start firecrawl.service
systemctl start chrome-cdp.service

echo ""
echo "==> Status:"
echo "--- firecrawl ---"
systemctl status firecrawl.service --no-pager -l || true
echo ""
echo "--- chrome-cdp ---"
systemctl status chrome-cdp.service --no-pager -l || true

echo ""
echo "============================================================"
echo " Services installed and started."
echo ""
echo "  firecrawl  → http://localhost:3002"
echo "  chrome CDP → http://localhost:9222"
echo ""
echo " Hermes gateway is managed by its own *user* service (run without sudo):"
echo "   hermes gateway status"
echo "   hermes gateway start / stop / restart / install"
echo "   journalctl --user -u hermes-gateway -f"
echo " It only starts at boot without login if lingering is on. Hermes tries to"
echo " enable it on install; if 'hermes doctor' reports it disabled, run:"
echo "   sudo loginctl enable-linger $SERVICE_USER"
echo ""
echo " Useful commands:"
echo "   sudo systemctl status  firecrawl chrome-cdp"
echo "   sudo systemctl restart firecrawl chrome-cdp"
echo "   sudo journalctl -u firecrawl -f"
echo "   sudo journalctl -u chrome-cdp -f"
echo "============================================================"
