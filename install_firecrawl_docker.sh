#!/usr/bin/env bash
# install_firecrawl_docker.sh
#
# Clones Firecrawl into ~/firecrawl and starts it with Docker Compose using
# prebuilt images. Safe to re-run: an existing .env is kept as-is.
#
# Usage:  bash install_firecrawl_docker.sh

set -euo pipefail

REPO_DIR="$HOME/firecrawl"

if ! command -v docker >/dev/null 2>&1; then
	echo "Docker is not installed or not in PATH."
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

# Use prebuilt images instead of building from source. These substitutions are
# idempotent; if upstream changes the compose layout they simply stop matching.
sed -i 's|# image: ghcr.io/firecrawl/firecrawl|image: ghcr.io/firecrawl/firecrawl|' docker-compose.yaml
sed -i 's|  build: apps/api|  # build: apps/api|' docker-compose.yaml
sed -i 's|# image: ghcr.io/firecrawl/playwright-service:latest|image: ghcr.io/firecrawl/playwright-service:latest|' docker-compose.yaml
sed -i 's|    build: apps/playwright-service-ts|    # build: apps/playwright-service-ts|' docker-compose.yaml

"${COMPOSE_CMD[@]}" up -d

cat << 'EOF'

Firecrawl is starting on http://localhost:3002

Point Hermes at it by adding this line to ~/.hermes/.env, then restart the gateway:
  FIRECRAWL_API_URL=http://localhost:3002

Note: the API has no authentication (USE_DB_AUTHENTICATION=false) and Docker
publishes port 3002 on all interfaces. Firewall it if this machine is reachable
from an untrusted network.
EOF
