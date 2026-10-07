#!/usr/bin/env bash
# chrome_remote_debug.sh
#
# Launches Chrome with remote debugging on port 9222 for interactive use.
# If the headless chrome-cdp systemd service is running it is stopped first,
# and automatically restarted when this script exits.

set -euo pipefail

PORT=9222
USER_DATA_DIR="$HOME/.config/google-chrome-ai-agent"
SERVICE="chrome-cdp.service"

# Same lookup as install_autostart_services.sh: Google Chrome, else the
# Playwright Chromium bundled with Hermes (Chrome has no Linux arm64 build).
CHROME_BIN="${CHROME_BIN:-$(command -v google-chrome || command -v google-chrome-stable || true)}"
if [[ -z "$CHROME_BIN" ]]; then
    CHROME_BIN=$(ls -1d "$HOME"/.hermes/tools/chromium-*/chrome-linux/chrome 2>/dev/null | sort -V | tail -n1 || true)
fi
if [[ -z "$CHROME_BIN" ]]; then
    echo "ERROR: no Chrome/Chromium found (install google-chrome or set CHROME_BIN=/path/to/chrome)" >&2
    exit 1
fi

port_in_use() {
    ss -tln | grep -q ":$PORT "
}

# ── Stop the headless service if it holds the port ───────────────────────────
if systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
    echo "==> Stopping headless $SERVICE to free port $PORT..."
    sudo systemctl stop "$SERVICE"
    # Restore the service when this script exits (Ctrl-C, close terminal, etc.)
    trap 'echo "==> Restarting headless $SERVICE..."; sudo systemctl start "$SERVICE"' EXIT
fi

# Wait up to 5 seconds for the port to be released
for _ in 1 2 3 4 5; do
    port_in_use || break
    sleep 1
done
if port_in_use; then
    echo "ERROR: port $PORT is still in use; Chrome would start without remote debugging." >&2
    echo "       Check what holds it:  ss -tlnp | grep :$PORT" >&2
    exit 1
fi

echo "==> Starting $CHROME_BIN with remote debugging on port $PORT"
echo "    CDP endpoint: http://localhost:$PORT"
echo "    Close this terminal or press Ctrl-C to stop Chrome and restore the headless service."
echo ""

"$CHROME_BIN" \
    --remote-debugging-port=$PORT \
    --user-data-dir="$USER_DATA_DIR"
