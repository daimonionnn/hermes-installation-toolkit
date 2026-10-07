#!/usr/bin/env bash
# install_firecrawl_docker.sh
#
# Clones Firecrawl into ~/firecrawl and starts it with Docker Compose using
# prebuilt images. Works on x86-64 and arm64 (e.g. Raspberry Pi 4/5).
#
# Safe to re-run: an existing .env is kept (missing tuning keys are appended),
# and a docker-compose.override.yaml you wrote yourself is never overwritten.
#
# Usage:  bash install_firecrawl_docker.sh

set -euo pipefail

REPO_DIR="$HOME/firecrawl"
OVERRIDE_MARKER="# Managed by install_firecrawl_docker.sh"

if ! command -v docker >/dev/null 2>&1; then
	echo "Docker is not installed or not in PATH. On Ubuntu:"
	echo "  sudo apt install -y docker.io docker-compose-v2 git"
	echo "  sudo usermod -aG docker \$USER   # then log out and back in"
	exit 1
fi

if docker compose version >/dev/null 2>&1; then
	COMPOSE_CMD=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
	COMPOSE_CMD=(docker-compose)
else
	echo "Docker Compose is not available (need 'docker compose' or 'docker-compose')."
	exit 1
fi

# ── Platform detection ────────────────────────────────────────────────────────
ARCH=$(uname -m)
IS_ARM64=false
case "$ARCH" in aarch64 | arm64) IS_ARM64=true ;; esac

MEM_GB=$(awk '/^MemTotal:/ {printf "%d", $2 / 1024 / 1024}' /proc/meminfo)
# Small boards and low-RAM PCs get a longer startup budget and less concurrency.
LOW_RESOURCE=false
if $IS_ARM64 || [ "$MEM_GB" -lt 12 ]; then
	LOW_RESOURCE=true
fi
echo "==> Platform: $ARCH, ${MEM_GB} GB RAM (low-resource tuning: $LOW_RESOURCE)"

if [ ! -d "$REPO_DIR/.git" ]; then
	git clone https://github.com/firecrawl/firecrawl.git "$REPO_DIR"
fi

cd "$REPO_DIR"

# Only create .env on first install; re-runs must not wipe keys added later.
if [ ! -f .env ]; then
	if command -v openssl >/dev/null 2>&1; then
		BULL_AUTH_KEY=$(openssl rand -hex 32)
	else
		BULL_AUTH_KEY=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
	fi
	cat > .env << EOF
PORT=3002
HOST=0.0.0.0
USE_DB_AUTHENTICATION=false
BULL_AUTH_KEY=$BULL_AUTH_KEY
EOF
	echo "Created $REPO_DIR/.env"
else
	echo "Keeping existing $REPO_DIR/.env"
fi

# Append tuning keys the user has not set yet (existing values always win).
if $LOW_RESOURCE; then
	TUNING=(
		HARNESS_STARTUP_TIMEOUT_MS=300000 # API startup exceeds the 60s default on a Pi
		NUM_WORKERS_PER_QUEUE=2
		CRAWL_CONCURRENT_REQUESTS=4
		MAX_CONCURRENT_JOBS=2
		BROWSER_POOL_SIZE=2
	)
	header_written=false
	for kv in "${TUNING[@]}"; do
		key=${kv%%=*}
		grep -q "^${key}=" .env && continue
		if ! $header_written; then
			printf '\n# Low-resource tuning (added by install_firecrawl_docker.sh)\n' >> .env
			header_written=true
		fi
		echo "$kv" >> .env
		echo "    .env: added $kv"
	done
fi

# Use prebuilt images instead of building from source. These substitutions are
# idempotent; if upstream changes the compose layout they simply stop matching.
sed -i 's|# image: ghcr.io/firecrawl/firecrawl|image: ghcr.io/firecrawl/firecrawl|' docker-compose.yaml
sed -i 's|  build: apps/api|  # build: apps/api|' docker-compose.yaml
sed -i 's|# image: ghcr.io/firecrawl/playwright-service:latest|image: ghcr.io/firecrawl/playwright-service:latest|' docker-compose.yaml
sed -i 's|    build: apps/playwright-service-ts|    # build: apps/playwright-service-ts|' docker-compose.yaml

# ── Compose override (auto-merged by docker compose) ──────────────────────────
if [ -f docker-compose.override.yaml ] && ! grep -qF "$OVERRIDE_MARKER" docker-compose.override.yaml; then
	echo "Keeping your own $REPO_DIR/docker-compose.override.yaml (not managed by this script)"
else
	{
		echo "$OVERRIDE_MARKER; edits are overwritten on re-run."
		echo "# Remove the first line to take ownership of this file."
		cat << 'EOF'
services:
  # The healthcheck runs `rabbitmq-diagnostics` via docker exec as root. If it
  # fires before the server is up it creates a root-owned .erlang.cookie that
  # the server (uid 999) can't read, and RabbitMQ exits with "eacces". Running
  # the whole container as 999 avoids that; the longer start_period covers slow
  # disks and SD cards.
  rabbitmq:
    user: "999:999"
    healthcheck:
      start_period: 120s
      retries: 10
  api:
    restart: unless-stopped
EOF
		if $IS_ARM64; then
			cat << 'EOF'
  # FoundationDB is an optional queue backend (NUQ_BACKEND=fdb; Postgres is the
  # default). Its arm64 build dies with SIGILL on older cores such as the
  # Raspberry Pi 4's Cortex-A72, so keep it out of the default stack.
  foundationdb:
    profiles: ["fdb"]
  foundationdb-init:
    profiles: ["fdb"]
EOF
		fi
	} > docker-compose.override.yaml
	echo "Wrote $REPO_DIR/docker-compose.override.yaml"
fi

"${COMPOSE_CMD[@]}" up -d --remove-orphans

# ── Wait for the API ──────────────────────────────────────────────────────────
WAIT_SECS=$($LOW_RESOURCE && echo 360 || echo 120)
echo ""
echo "==> Waiting up to ${WAIT_SECS}s for the API on http://localhost:3002 ..."
ready=false
for _ in $(seq 1 $((WAIT_SECS / 5))); do
	if curl -fs -o /dev/null http://localhost:3002/; then
		ready=true
		break
	fi
	sleep 5
done
if $ready; then
	echo "    API is up."
else
	echo "    API not answering yet. It may still be starting; check with:"
	echo "      cd $REPO_DIR && ${COMPOSE_CMD[*]} ps && ${COMPOSE_CMD[*]} logs --tail 50 api rabbitmq"
fi

cat << 'EOF'

Firecrawl runs on http://localhost:3002

Point Hermes at it by adding this line to ~/.hermes/.env, then restart the gateway:
  FIRECRAWL_API_URL=http://localhost:3002

Note: the API has no authentication (USE_DB_AUTHENTICATION=false) and Docker
publishes port 3002 on all interfaces. Firewall it if this machine is reachable
from an untrusted network.
EOF
