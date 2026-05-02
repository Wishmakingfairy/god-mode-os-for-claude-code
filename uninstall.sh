#!/bin/bash
# god-mode-os uninstall
# Usage: ./uninstall.sh [--keep-data]
#
# Removes:
#   - all god-mode-os symlinks from ~/.claude/hooks/
#   - all god-mode-os entries from ~/.claude/settings.json
#   - launchd plists from ~/Library/LaunchAgents/
#   - Postgres docker container (router tier)
# Restores ~/.claude/settings.json from backup if present.
#
# Keeps ~/.god-mode-os/ data (logs, retros, configs) by default.
# Pass --keep-data to keep, or --purge to delete everything.

set -euo pipefail

GMOS_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GMOS_HOME="${GMOS_HOME:-$HOME/.god-mode-os}"
CC_HOOKS_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"
BACKUP="$HOME/.claude/settings.json.gmos-backup"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
MODE="${1:---keep-data}"

echo "==> Removing god-mode-os symlinks from $CC_HOOKS_DIR"
for f in install-guard folder-law-reminder stop-validator session-retro discipline-toggle context-router; do
    if [ -L "$CC_HOOKS_DIR/$f.sh" ] && [[ "$(readlink "$CC_HOOKS_DIR/$f.sh")" == "$GMOS_REPO"* ]]; then
        rm "$CC_HOOKS_DIR/$f.sh"
        echo "    removed $f.sh"
    fi
done

echo "==> Removing god-mode-os entries from $SETTINGS"
if [ -f "$SETTINGS" ]; then
    if [ -f "$BACKUP" ]; then
        read -p "    Restore ~/.claude/settings.json from backup? This will overwrite recent edits. (y/N) " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "    Restoring from $BACKUP"
            cp "$BACKUP" "$SETTINGS"
            rm "$BACKUP"
        else
            echo "    Skipping backup restore."
        fi
    elif command -v jq >/dev/null 2>&1; then
        # Strip any hook entries whose command points at $GMOS_REPO
        tmp=$(mktemp)
        jq --arg repo "$GMOS_REPO" '
            if .hooks then
                .hooks |= with_entries(
                    .value |= map(
                        .hooks |= map(select(.command | contains($repo) | not))
                    ) |
                    .value |= map(select(.hooks | length > 0))
                )
            else . end
        ' "$SETTINGS" > "$tmp"
        mv "$tmp" "$SETTINGS"
        echo "    cleaned via jq"
    fi
fi

echo "==> Unloading launchd plists"
for plist in com.god-mode-os.intelligence-monitor com.god-mode-os.three-day-overview; do
    target="$LAUNCH_AGENTS/$plist.plist"
    if [ -f "$target" ]; then
        launchctl unload "$target" 2>/dev/null || true
        rm "$target"
        echo "    removed $plist"
    fi
done

if [ -f "$GMOS_REPO/router/docker-compose.yml" ]; then
    if command -v docker >/dev/null 2>&1 && docker ps -a --format '{{.Names}}' | grep -q gmos-postgres; then
        echo "==> Stopping Postgres container"
        docker compose -f "$GMOS_REPO/router/docker-compose.yml" down
        if [ "$MODE" = "--purge" ]; then
            docker compose -f "$GMOS_REPO/router/docker-compose.yml" down -v
            echo "    volume purged"
        fi
    fi
fi

if [ "$MODE" = "--purge" ]; then
    echo "==> Removing $GMOS_HOME (--purge)"
    rm -rf "$GMOS_HOME"
fi

echo ""
echo "Uninstalled. Restart Claude Code to clear hooks from active session."
[ "$MODE" != "--purge" ] && echo "Data kept at $GMOS_HOME (pass --purge to delete everything)."
