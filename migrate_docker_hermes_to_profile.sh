#!/usr/bin/env bash
# migrate_docker_hermes_to_profile.sh
#
# Copies the data directory of a Docker Hermes instance (default
# ~/.hermes-secondary) into a bare-metal Hermes profile, so the second agent
# runs natively next to your main one — same config, skills, sessions, memory
# and bot token, no container.
#
# The Docker data directory is only read, never modified, so the container
# stays usable as a fallback. Nothing is started: the script prints the
# commands to test the profile and install its gateway service.
#
# Usage:  bash migrate_docker_hermes_to_profile.sh [profile_name]
#         bash migrate_docker_hermes_to_profile.sh research
#         SRC_DIR=~/.hermes-research bash migrate_docker_hermes_to_profile.sh research
#         DRY_RUN=1 bash migrate_docker_hermes_to_profile.sh   # show, don't copy
#
# Environment:
#   SRC_DIR   Docker data directory to copy from (default: ~/.hermes-secondary)
#   DRY_RUN   Set to 1 to list what would be copied and exit
#
# Full guide: Doc/run-multiple-hermes-profiles.md

set -euo pipefail

PROFILE="${1:-secondary}"
SRC_DIR="${SRC_DIR:-$HOME/.hermes-secondary}"
HERMES_ROOT="${HERMES_ROOT:-$HOME/.hermes}"
DST_DIR="$HERMES_ROOT/profiles/$PROFILE"
DRY_RUN="${DRY_RUN:-0}"

# Container-built binaries, lazily installed Python packages and runtime state.
# All of it is either wrong for the host (compiled against the image) or
# regenerated on first start — copying it causes more harm than good.
EXCLUDES=(
    bin/ lazy-packages/ .local/ home/
    cache/ audio_cache/ image_cache/ logs/
    sandboxes/ terminal-sessions/ pending_messages/
    gateway/ gateway.lock gateway.pid gateway-starts.log gateway_state.json
    auth.lock '*.dispatch.lock' '*.init.lock'
    '*.bak' '*.bak-*' '*.bak.*'
    .skills_prompt_snapshot.json 'models_dev_cache.*'
    provider_models_cache.json ollama_cloud_models_cache.json
    interrupt_debug.log
)

# ── Preflight ─────────────────────────────────────────────────────────────────
if ! command -v hermes > /dev/null 2>&1; then
    echo "ERROR: 'hermes' is not in PATH. Install Hermes on this machine first." >&2
    exit 1
fi

if ! command -v rsync > /dev/null 2>&1; then
    echo "ERROR: rsync is required.  sudo apt install -y rsync" >&2
    exit 1
fi

if [[ ! -f "$SRC_DIR/config.yaml" ]]; then
    echo "ERROR: $SRC_DIR/config.yaml not found — is that the Docker data directory?" >&2
    echo "       Point the script at the right one:  SRC_DIR=/path/to/data $0 $PROFILE" >&2
    exit 1
fi

if [[ "$SRC_DIR" == "$HERMES_ROOT" ]]; then
    echo "ERROR: refusing to migrate $HERMES_ROOT into itself." >&2
    exit 1
fi

# A running container holds its own locks and may write while we read.
if command -v docker > /dev/null 2>&1; then
    RUNNING=$(docker ps --format '{{.Names}}' 2> /dev/null | while read -r c; do
        docker inspect "$c" --format '{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}' 2> /dev/null \
            | grep -qxF "$SRC_DIR" && echo "$c"
    done || true)
    if [[ -n "$RUNNING" ]]; then
        echo "ERROR: container(s) still using $SRC_DIR: $RUNNING" >&2
        echo "       Stop it first:  bash docker/hermes_docker_secondary.sh stop" >&2
        exit 1
    fi
fi

echo "==> Source (Docker data, read-only): $SRC_DIR"
echo "==> Target profile:                  $PROFILE  →  $DST_DIR"

RSYNC_ARGS=(-a)
for e in "${EXCLUDES[@]}"; do RSYNC_ARGS+=(--exclude "$e"); done

if [[ "$DRY_RUN" == "1" ]]; then
    echo "==> DRY_RUN=1 — top-level entries that would be copied:"
    rsync "${RSYNC_ARGS[@]}" --dry-run --out-format='%n' "$SRC_DIR/" "$DST_DIR/" \
        | awk -F/ 'NF && $1 != "" {print $1}' | sort -u | sed 's/^/      /'
    exit 0
fi

# ── 1. Create the profile (registers it with `hermes profile list`) ───────────
if [[ -d "$DST_DIR" ]]; then
    echo "==> Profile directory already exists — copying into it"
else
    # --no-skills: the skills we copy from the Docker instance replace them.
    hermes profile create "$PROFILE" --no-skills \
        --description "Migrated from the Docker Hermes instance at $SRC_DIR"
fi

# ── 2. Copy the data ──────────────────────────────────────────────────────────
echo "==> Copying data (this keeps $SRC_DIR untouched)"
UNREADABLE=$(find "$SRC_DIR" -mindepth 1 \
    \( -name bin -o -name lazy-packages -o -name .local -o -name home -o -name cache \) -prune \
    -o ! -readable -print 2> /dev/null || true)

# Files written by the container's own uid cannot be read as this user; they are
# caches, usage counters and old sessions, all of which Hermes regenerates.
# Those denials are reported in the summary below, so drop the raw rsync noise
# and keep anything else it has to say.
RSYNC_ERR=$(mktemp)
rsync "${RSYNC_ARGS[@]}" "$SRC_DIR/" "$DST_DIR/" 2> "$RSYNC_ERR" || true
grep -v -e 'Permission denied (13)' -e 'some files/attrs were not transferred' \
    "$RSYNC_ERR" >&2 || true
rm -f "$RSYNC_ERR"

# Let `hermes update` sync bundled skills into this profile like any other.
rm -f "$DST_DIR/.no-bundled-skills"

# ── 3. Rewrite container-only addresses ───────────────────────────────────────
# Inside a container the host is host.docker.internal / the bridge gateway.
# On bare metal the same services are plain loopback.
echo "==> Rewriting container addresses to 127.0.0.1"
for f in "$DST_DIR/config.yaml" "$DST_DIR/.env"; do
    [[ -f "$f" ]] || continue
    if grep -qE 'host\.docker\.internal|172\.17\.0\.1' "$f"; then
        cp -p "$f" "$f.bak-premigration"
        sed -i -e 's/host\.docker\.internal/127.0.0.1/g' -e 's/172\.17\.0\.1/127.0.0.1/g' "$f"
        echo "    $(basename "$f"): rewritten (backup: $(basename "$f").bak-premigration)"
    fi
done

# ── 4. Tools the container shipped in its own bin/ ────────────────────────────
# tirith is the command scanner Hermes calls through PATH; the container build
# was excluded above, so reuse the one from the main install.
if [[ -x "$HERMES_ROOT/bin/tirith" && ! -x "$DST_DIR/bin/tirith" ]]; then
    mkdir -p "$DST_DIR/bin"
    cp -p "$HERMES_ROOT/bin/tirith" "$DST_DIR/bin/tirith"
    echo "==> Copied tirith security scanner from the main install"
fi

# ── 5. Report what needs a human decision ────────────────────────────────────
echo ""
echo "==> Done. Things worth checking:"

if [[ -n "$UNREADABLE" ]]; then
    COUNT=$(printf '%s\n' "$UNREADABLE" | grep -c . || true)
    echo "    • $COUNT file(s) owned by the container user could not be read and were"
    echo "      skipped (caches, skill usage counters, old sessions). Hermes rebuilds them:"
    printf '%s\n' "$UNREADABLE" | sed "s|^$SRC_DIR/|        |" | head -10
fi

tok() { grep -m1 -E '^TELEGRAM_BOT_TOKEN=.+' "$1" 2> /dev/null | cut -d= -f2- | cut -d: -f1; }
MAIN_BOT=$(tok "$HERMES_ROOT/.env")
PROF_BOT=$(tok "$DST_DIR/.env")
if [[ -n "$PROF_BOT" ]]; then
    if [[ "$PROF_BOT" == "$MAIN_BOT" ]]; then
        echo "    • Telegram bot $PROF_BOT is the SAME as the main profile's. Two gateways"
        echo "      polling one bot steal each other's messages — use a second bot."
    else
        echo "    • Telegram bot $PROF_BOT (main profile uses ${MAIN_BOT:-none}) — different"
        echo "      bots, so both gateways can run at the same time."
    fi
    echo "    • Never run this profile's gateway while the Docker container is up:"
    echo "      both read $SRC_DIR's bot token and would fight over it."
fi

if grep -qE '^API_SERVER_ENABLED=true' "$DST_DIR/.env" 2> /dev/null; then
    PORT=$(grep -m1 -E '^API_SERVER_PORT=' "$DST_DIR/.env" | cut -d= -f2- || true)
    echo "    • API server is enabled on port ${PORT:-8642} — give it a free port"
    echo "      (the main profile owns 8642) in $DST_DIR/.env"
fi

cat << EOF

Next steps:
  $PROFILE chat -q "say ok"          # test the profile (wrapper script)
  $PROFILE gateway install --no-start-on-login --start-now
  $PROFILE gateway status            # start / stop / restart it the same way

The Docker instance was not modified. Bring it back any time with:
  bash docker/hermes_docker_secondary.sh start
EOF
