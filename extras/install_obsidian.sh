#!/usr/bin/env bash
# install_obsidian.sh
#
# Installs Obsidian (latest .deb) and pre-installs the recommended community
# plugins into a vault of your choice. Run once; re-run safely to update.
#
# Usage:
#   bash install_obsidian.sh                   # installs to ~/Obsidian
#   bash install_obsidian.sh ~/Documents/Notes # custom vault path

set -euo pipefail

VAULT_DIR="${1:-$HOME/Obsidian}"
PLUGINS_DIR="$VAULT_DIR/.obsidian/plugins"

# ── Plugins: (plugin-id  github-repo) ────────────────────────────────────────
declare -A PLUGINS=(
    [obsidian-kanban]="mgmeyers/obsidian-kanban"
    [dataview]="blacksmithgu/obsidian-dataview"
    [templater-obsidian]="SilentVoid13/Templater"
    [obsidian-git]="denolehov/obsidian-git"
    [obsidian-tasks-plugin]="obsidian-tasks-group/obsidian-tasks"
    [obsidian-excalidraw-plugin]="zsviczian/obsidian-excalidraw-plugin"
    [calendar]="liamcain/obsidian-calendar-plugin"
    [quickadd]="chhoumann/quickadd"
    [table-editor-obsidian]="tgrosinger/advanced-tables-obsidian"
    [smart-connections]="brianpetro/obsidian-smart-connections"
    [copilot]="logancyang/obsidian-copilot"
)

# ── Install Obsidian ──────────────────────────────────────────────────────────
install_obsidian() {
    if command -v obsidian &>/dev/null; then
        echo "==> Obsidian already installed, skipping download."
        return
    fi

    echo "==> Fetching latest Obsidian version..."
    local version
    version=$(curl -s https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4 | tr -d 'v' || true)
    if [[ -z "$version" ]]; then
        echo "ERROR: could not determine the latest Obsidian version (GitHub API rate limit?)." >&2
        exit 1
    fi
    local deb_url="https://github.com/obsidianmd/obsidian-releases/releases/download/v${version}/obsidian_${version}_amd64.deb"

    echo "==> Downloading Obsidian v${version}..."
    wget -q --show-progress -O /tmp/obsidian.deb "$deb_url"
    echo "==> Installing Obsidian..."
    sudo dpkg -i /tmp/obsidian.deb || sudo apt-get install -f -y
    rm /tmp/obsidian.deb
    echo "    Obsidian installed."
}

# ── Download a single plugin from its latest GitHub release ──────────────────
install_plugin() {
    local plugin_id="$1"
    local repo="$2"
    local dir="$PLUGINS_DIR/$plugin_id"

    mkdir -p "$dir"

    local base_url="https://github.com/$repo/releases/latest/download"
    local updated=false

    for file in main.js manifest.json styles.css; do
        local url="$base_url/$file"
        local dest="$dir/$file"

        # styles.css is optional — skip cleanly if not found
        local http_code
        http_code=$(curl -sLo "$dest" -w "%{http_code}" "$url" 2>/dev/null || echo "000")
        if [[ "$http_code" == "200" ]]; then
            updated=true
        else
            rm -f "$dest"
        fi
    done

    if $updated; then
        echo "    ✔ $plugin_id"
    else
        echo "    ✗ $plugin_id (download failed — check repo: $repo)"
    fi
}

# ── Write .obsidian config files ──────────────────────────────────────────────
# Each file is written only if it doesn't exist yet, so re-running the script
# updates plugin binaries without resetting settings changed in Obsidian.
write_if_missing() {
    local file="$1"
    if [[ -e "$file" ]]; then
        echo "    keeping existing $(basename "$file")"
        cat > /dev/null
    else
        cat > "$file"
    fi
}

write_obsidian_config() {
    local obsidian_dir="$VAULT_DIR/.obsidian"
    mkdir -p "$obsidian_dir"

    # Enable all community plugins
    local plugin_list
    plugin_list=$(printf '"%s",' "${!PLUGINS[@]}" | sed 's/,$//')
    write_if_missing "$obsidian_dir/community-plugins.json" <<EOF
[$plugin_list]
EOF

    # Enable community plugins (disable restricted mode)
    write_if_missing "$obsidian_dir/app.json" <<EOF
{
  "enabledCssSnippets": [],
  "communityPlugins": true
}
EOF

    # Enable useful built-in core plugins
    write_if_missing "$obsidian_dir/core-plugins.json" <<EOF
{
  "file-explorer": true,
  "global-search": true,
  "switcher": true,
  "graph": true,
  "backlink": true,
  "canvas": true,
  "outgoing-link": true,
  "tag-pane": true,
  "properties": true,
  "page-preview": true,
  "daily-notes": true,
  "templates": true,
  "note-composer": true,
  "command-palette": true,
  "word-count": true,
  "outline": true,
  "bookmarks": true
}
EOF
}

# ── Main ──────────────────────────────────────────────────────────────────────
echo ""
echo "=== Obsidian Installer ==="
echo "    Vault: $VAULT_DIR"
echo ""

install_obsidian

echo ""
echo "==> Creating vault at: $VAULT_DIR"
mkdir -p "$VAULT_DIR"

echo "==> Downloading ${#PLUGINS[@]} community plugins..."
for plugin_id in "${!PLUGINS[@]}"; do
    install_plugin "$plugin_id" "${PLUGINS[$plugin_id]}"
done

echo ""
echo "==> Writing .obsidian config..."
write_obsidian_config

echo ""
echo "============================================================"
echo " Done! Open Obsidian and open this folder as your vault:"
echo "   $VAULT_DIR"
echo ""
echo " Installed plugins:"
echo "   Kanban           – visual task boards"
echo "   Dataview         – query notes like a database"
echo "   Templater        – advanced templates"
echo "   Git              – auto-commit vault to git"
echo "   Tasks            – cross-note task tracking"
echo "   Excalidraw       – diagrams and sketches in notes"
echo "   Calendar         – visual calendar for daily notes"
echo "   QuickAdd         – fast note capture"
echo "   Advanced Tables  – proper table editing"
echo "   Smart Connections – semantic similarity search"
echo "   Copilot          – AI chat with your vault"
echo ""
echo " First launch: Settings → Community plugins → click Enable on each plugin"
echo "============================================================"
