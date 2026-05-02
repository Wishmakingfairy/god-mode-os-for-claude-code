#!/bin/bash
# god-mode-os install
# Usage:
#   ./install.sh                  # installs Discipline tier (default, 60s)
#   ./install.sh discipline       # same as above
#   ./install.sh routing          # adds Routing tier (requires Docker + Ollama)
#   ./install.sh intelligence     # adds Intelligence tier (requires Gemini CLI optional)
#   ./install.sh all              # installs everything
#
# Idempotent: re-running adds missing pieces, never duplicates settings.json entries.
# Backs up ~/.claude/settings.json to settings.json.gmos-backup before any change.

set -euo pipefail

GMOS_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GMOS_HOME="${GMOS_HOME:-$HOME/.god-mode-os}"
CC_HOOKS_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"
BACKUP="$HOME/.claude/settings.json.gmos-backup"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"

TIER="${1:-discipline}"

mkdir -p "$GMOS_HOME" "$CC_HOOKS_DIR"

# Pre-flight
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required. brew install jq"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 required"; exit 1; }

backup_settings() {
    if [ -f "$SETTINGS" ] && [ ! -f "$BACKUP" ]; then
        cp "$SETTINGS" "$BACKUP"
        echo "    Backed up $SETTINGS -> $BACKUP"
    elif [ ! -f "$SETTINGS" ]; then
        echo '{}' > "$SETTINGS"
    fi
}

# Symlink (not copy) so updates flow through git pull
link_hook() {
    local src="$1" dst="$CC_HOOKS_DIR/$(basename "$1")"
    ln -sf "$src" "$dst"
    echo "    linked $(basename "$src")"
}

# Add a hook entry to settings.json under .hooks.<event>[].hooks[]
register_hook() {
    local event="$1" hook_path="$2"
    local tmp
    tmp=$(mktemp)
    jq --arg event "$event" --arg cmd "bash $hook_path" '
        .hooks //= {} |
        .hooks[$event] //= [] |
        if (.hooks[$event] | map(.hooks // []) | flatten | map(.command) | index($cmd)) == null then
            .hooks[$event] += [{"hooks": [{"type": "command", "command": $cmd}]}]
        else . end
    ' "$SETTINGS" > "$tmp"
    mv "$tmp" "$SETTINGS"
    echo "    registered $(basename "$hook_path") on $event"
}

install_discipline() {
    echo "==> Installing Discipline tier"
    backup_settings
    for h in install-guard folder-law-reminder; do
        link_hook "$GMOS_REPO/hooks/discipline/$h.sh"
        register_hook "PreToolUse" "$CC_HOOKS_DIR/$h.sh"
    done
    link_hook "$GMOS_REPO/hooks/discipline/stop-validator.sh"
    register_hook "Stop" "$CC_HOOKS_DIR/stop-validator.sh"
    link_hook "$GMOS_REPO/hooks/discipline/session-retro.sh"
    register_hook "Stop" "$CC_HOOKS_DIR/session-retro.sh"
    link_hook "$GMOS_REPO/hooks/discipline/discipline-toggle.sh"

    # Seed example configs if user hasn't created theirs
    [ -f "$GMOS_HOME/protected-paths.txt" ] || cp "$GMOS_REPO/install/protected-paths.txt.example" "$GMOS_HOME/protected-paths.txt"
    [ -f "$GMOS_HOME/forbidden-write-paths.txt" ] || cp "$GMOS_REPO/install/forbidden-write-paths.txt.example" "$GMOS_HOME/forbidden-write-paths.txt"

    echo ""
    echo "Discipline tier installed."
    echo "Kill switch: bash $GMOS_REPO/hooks/discipline/discipline-toggle.sh off"
    echo "Try it: open Claude Code and ask it to mark something done. stop-validator will catch a false done."
}

install_routing() {
    echo "==> Installing Routing tier"
    command -v docker >/dev/null 2>&1 || { echo "ERROR: docker required"; exit 1; }
    command -v ollama >/dev/null 2>&1 || { echo "ERROR: ollama required (brew install ollama && ollama serve)"; exit 1; }

    bash "$GMOS_REPO/router/setup.sh"

    backup_settings
    link_hook "$GMOS_REPO/hooks/routing/context-router.sh"
    register_hook "UserPromptSubmit" "$CC_HOOKS_DIR/context-router.sh"

    # Point the hook at the real query.py
    cat >> "$GMOS_HOME/env" <<EOF
export GMOS_ROUTER_QUERY="$GMOS_REPO/router/vector/query.py"
export GMOS_DB_DSN="host=localhost port=5433 dbname=gmos_router user=gmos password=gmos"
EOF
    echo ""
    echo "Routing tier installed."
    echo "Test: python3 $GMOS_REPO/router/vector/query.py 'how do I optimize a postgres query' --merged"
}

install_intelligence() {
    echo "==> Installing Intelligence tier"
    for plist in com.god-mode-os.intelligence-monitor com.god-mode-os.three-day-overview; do
        local src="$GMOS_REPO/install/$plist.plist.example"
        local dst="$LAUNCH_AGENTS/$plist.plist"
        sed "s|REPLACE_WITH_REPO_PATH|$GMOS_REPO|g; s|REPLACE_WITH_HOME|$HOME|g" "$src" > "$dst"
        launchctl unload "$dst" 2>/dev/null || true
        launchctl load "$dst"
        echo "    installed $plist (loaded)"
    done

    [ -f "$GMOS_HOME/feeds.txt" ] || cp "$GMOS_REPO/install/feeds.txt.example" "$GMOS_HOME/feeds.txt"
    [ -f "$GMOS_HOME/health-check-urls.txt" ] || cp "$GMOS_REPO/install/health-check-urls.txt.example" "$GMOS_HOME/health-check-urls.txt"

    echo ""
    echo "Intelligence tier installed."
    echo "First digest: bash $GMOS_REPO/hooks/intelligence/intelligence-monitor.sh"
    echo "Edit feeds:   $GMOS_HOME/feeds.txt"
    echo "Edit health:  $GMOS_HOME/health-check-urls.txt"
    if ! command -v gemini >/dev/null 2>&1; then
        echo ""
        echo "    Optional: install Gemini CLI for summarized digests."
        echo "    npm install -g @google/gemini-cli && gemini auth"
    fi
}

case "$TIER" in
    discipline) install_discipline ;;
    routing) install_routing ;;
    intelligence) install_intelligence ;;
    all)
        install_discipline
        echo ""
        install_routing
        echo ""
        install_intelligence
        ;;
    *)
        echo "Unknown tier: $TIER"
        echo "Usage: $0 [discipline|routing|intelligence|all]"
        exit 1
        ;;
esac

echo ""
echo "Done. Restart Claude Code to activate hooks."
