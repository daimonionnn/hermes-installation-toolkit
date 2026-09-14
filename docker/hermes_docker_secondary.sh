#!/usr/bin/env bash
set -euo pipefail

CONTAINER_CLI="${CONTAINER_CLI:-docker}"
COMPOSE_CLI="${COMPOSE_CLI:-docker compose}"
PROJECT_NAME="${HERMES_SECONDARY_PROJECT:-hermes-secondary}"
CONTAINER_NAME="${HERMES_SECONDARY_CONTAINER:-hermes-secondary}"
IMAGE="${HERMES_SECONDARY_IMAGE:-nousresearch/hermes-agent:latest}"
DATA_DIR="${HERMES_SECONDARY_DATA_DIR:-$HOME/.hermes-secondary}"
API_PORT="${HERMES_SECONDARY_API_PORT:-8643}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.hermes-secondary.yml"

usage() {
  cat <<EOF
Usage: $0 <command>

Commands:
  setup     Run the one-time interactive Hermes setup wizard in Docker
  start     Start the secondary Hermes gateway container
  stop      Stop the secondary Hermes gateway container
  restart   Restart the secondary Hermes gateway container
  logs      Follow secondary Hermes gateway logs
  shell     Open a shell with Hermes already on PATH
  pull      Pull the latest Hermes Docker image
  status    Show container status

Environment overrides:
  HERMES_SECONDARY_DATA_DIR    Data directory (default: $HOME/.hermes-secondary)
  HERMES_SECONDARY_API_PORT    Host API port (default: 8643)
  HERMES_SECONDARY_CONTAINER   Container name (default: hermes-secondary)
  HERMES_SECONDARY_IMAGE       Image (default: nousresearch/hermes-agent:latest)
  CONTAINER_CLI                Container CLI (default: docker)
  COMPOSE_CLI                  Compose CLI (default: docker compose)
EOF
}

compose() {
  HERMES_UID="$(id -u)" \
  HERMES_GID="$(id -g)" \
  HERMES_SECONDARY_DATA_DIR="$DATA_DIR" \
  HERMES_SECONDARY_API_PORT="$API_PORT" \
  HERMES_SECONDARY_CONTAINER="$CONTAINER_NAME" \
  HERMES_SECONDARY_IMAGE="$IMAGE" \
    $COMPOSE_CLI -p "$PROJECT_NAME" -f "$COMPOSE_FILE" "$@"
}

ensure_data_dir() {
  mkdir -p "$DATA_DIR"
}

cmd="${1:-}"
case "$cmd" in
  setup)
    ensure_data_dir
    "$CONTAINER_CLI" run -it --rm \
      --name "${CONTAINER_NAME}-setup" \
      --add-host=host.docker.internal:host-gateway \
      -v "$DATA_DIR:/opt/data" \
      -e HERMES_UID="$(id -u)" \
      -e HERMES_GID="$(id -g)" \
      "$IMAGE" setup
    ;;
  start)
    ensure_data_dir
    compose up -d
    ;;
  stop)
    compose down
    ;;
  restart)
    compose restart
    ;;
  logs)
    compose logs -f --tail=100
    ;;
  shell)
    "$CONTAINER_CLI" exec -it "$CONTAINER_NAME" bash -lc 'export PATH="/opt/hermes/.venv/bin:$PATH"; exec bash -i'
    ;;
  pull)
    compose pull
    ;;
  status)
    compose ps
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    usage >&2
    exit 1
    ;;
esac
