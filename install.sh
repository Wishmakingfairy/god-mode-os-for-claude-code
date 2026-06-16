#!/bin/bash
# god-mode-os install
# Usage:
#   ./install.sh                  # installs Discipline tier (default, 60s)
#   ./install.sh discipline       # same as above
#   ./install.sh routing          # adds Routing tier (requires Docker + Ollama)
#   ./install.sh all              # discipline + routing
#   ./install.sh all              # installs everything
#
# Idempotent: re-running adds missing pieces, never duplicates settings.json entries.
# Backs up ~/.claude/settings.json to settings.json.gmos-backup before any change.

set -euo pipefail

# Required environment
if [ -z "${HOME:-}" ]; then
    echo "ERROR: \$HOME is not set. god-mode-os installs into \$HOME/.claude/."
    exit 1
fi

# Normalize $HOME (strip trailing slash so substring/prefix checks behave).
HOME="${HOME%/}"

GMOS_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GMOS_REPO="${GMOS_REPO%/}"
GMOS_HOME="${GMOS_HOME:-$HOME/.god-mode-os}"
GMOS_HOME="${GMOS_HOME%/}"
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
    if [ -f "$SETTINGS" ]; then
        # Refuse to touch invalid JSON. Better to bail before any change than
        # leave a half-installed state on top of a broken config.
        if ! jq empty "$SETTINGS" >/dev/null 2>&1; then
            echo "ERROR: $SETTINGS is not valid JSON."
            echo "       Fix or remove it before installing god-mode-os."
            echo "       (Refusing to modify a corrupt config file.)"
            exit 1
        fi
        if [ ! -f "$BACKUP" ]; then
            cp "$SETTINGS" "$BACKUP"
            echo "    Backed up $SETTINGS -> $BACKUP"
        fi
    else
        echo '{}' > "$SETTINGS"
    fi
}

# Symlink (not copy) so updates flow through git pull. Refuses to overwrite
# pre-existing symlinks/files that did not come from this repo, to avoid
# silently breaking another user-installed tool.
link_hook() {
    local src="$1"
    local dst
    dst="$CC_HOOKS_DIR/$(basename "$1")"
    if [ -L "$dst" ]; then
        local current
        current=$(readlink "$dst" 2>/dev/null || echo "")
        if [ -n "$current" ] && [[ "$current" != "$GMOS_REPO"* ]]; then
            echo "    SKIPPED $(basename "$src"): $dst already exists pointing at $current"
            echo "    (remove or rename it manually, then re-run install)"
            return 1
        fi
    elif [ -e "$dst" ]; then
        echo "    SKIPPED $(basename "$src"): $dst already exists as a regular file"
        echo "    (remove or rename it manually, then re-run install)"
        return 1
    fi
    ln -sf "$src" "$dst"
    echo "    linked $(basename "$src")"
}

# Add a hook entry to settings.json under .hooks.<event>[].hooks[].
# Path is shell-quoted so paths containing spaces work when Claude Code runs them.
register_hook() {
    local event="$1" hook_path="$2"
    local tmp cmd
    tmp=$(mktemp) || { echo "ERROR: mktemp failed (disk full or /tmp not writable?)"; exit 1; }
    cmd=$(printf 'bash %q' "$hook_path")
    jq --arg event "$event" --arg cmd "$cmd" '
        .hooks //= {} |
        .hooks[$event] //= [] |
        if (.hooks[$event] | map(.hooks // []) | flatten | map(.command) | index($cmd)) == null then
            .hooks[$event] += [{"hooks": [{"type": "command", "command": $cmd}]}]
        else . end
    ' "$SETTINGS" > "$tmp"
    # Use cat instead of mv so we write through symlinks (some users symlink
    # ~/.claude/settings.json to a dotfiles repo).
    cat "$tmp" > "$SETTINGS"
    rm -f "$tmp"
    echo "    registered $(basename "$hook_path") on $event"
}

install_discipline() {
    echo "==> Installing Discipline tier"
    backup_settings
    for h in install-guard folder-law-reminder; do
        if link_hook "$GMOS_REPO/hooks/discipline/$h.sh"; then
            register_hook "PreToolUse" "$CC_HOOKS_DIR/$h.sh"
        fi
    done
    if link_hook "$GMOS_REPO/hooks/discipline/stop-validator.sh"; then
        register_hook "Stop" "$CC_HOOKS_DIR/stop-validator.sh"
    fi
    if link_hook "$GMOS_REPO/hooks/discipline/session-retro.sh"; then
        register_hook "Stop" "$CC_HOOKS_DIR/session-retro.sh"
    fi
    link_hook "$GMOS_REPO/hooks/discipline/discipline-toggle.sh" || true

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

    # Drop a marker BEFORE touching Docker so a partial setup is still uninstallable.
    touch "$GMOS_HOME/routing-installed"

    bash "$GMOS_REPO/router/setup.sh"

    backup_settings
    if link_hook "$GMOS_REPO/hooks/routing/context-router.sh"; then
        register_hook "UserPromptSubmit" "$CC_HOOKS_DIR/context-router.sh"
    fi

    # Write env file with values shell-quoted so paths containing spaces or
    # variable-looking substrings ($foo) survive.
    {
        printf 'export GMOS_ROUTER_QUERY=%q\n' "$GMOS_REPO/router/vector/query.py"
        printf 'export GMOS_DB_DSN=%q\n' "host=localhost port=5433 dbname=gmos_router user=gmos password=gmos"
    } >> "$GMOS_HOME/env"

    echo ""
    echo "Routing tier installed."
    echo "Test: python3 $GMOS_REPO/router/vector/query.py 'how do I optimize a postgres query' --merged"
}

case "$TIER" in
    discipline) install_discipline ;;
    routing) install_routing ;;
    all)
        install_discipline
        echo ""
        install_routing
        ;;
    *)
        echo "Unknown tier: $TIER"
        echo "Usage: $0 [discipline|routing|all]"
        exit 1
        ;;
esac

echo ""
echo "Done. Restart Claude Code to activate hooks."
