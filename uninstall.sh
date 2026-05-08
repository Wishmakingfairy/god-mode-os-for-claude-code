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

if [ -z "${HOME:-}" ]; then
    echo "ERROR: \$HOME is not set."
    exit 1
fi

HOME="${HOME%/}"
GMOS_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GMOS_REPO="${GMOS_REPO%/}"
GMOS_HOME="${GMOS_HOME:-$HOME/.god-mode-os}"
GMOS_HOME="${GMOS_HOME%/}"
CC_HOOKS_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"
BACKUP="$HOME/.claude/settings.json.gmos-backup"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
MODE="${1:---keep-data}"

echo "==> Removing god-mode-os symlinks from $CC_HOOKS_DIR"
REMOVED_CMDS=()
for f in install-guard folder-law-reminder stop-validator session-retro discipline-toggle context-router intelligence-trigger; do
    link="$CC_HOOKS_DIR/$f.sh"
    if [ -L "$link" ] && [[ "$(readlink "$link")" == "$GMOS_REPO"* ]]; then
        # Match the shell-quoted form install.sh registered (handles paths with spaces).
        REMOVED_CMDS+=("$(printf 'bash %q' "$link")")
        rm "$link"
        echo "    removed $f.sh"
    fi
done

echo "==> Removing god-mode-os entries from $SETTINGS"
if [ -f "$SETTINGS" ]; then
    # Decide whether to restore from backup. Only prompt when interactive.
    RESTORE=""
    if [ -f "$BACKUP" ] && [ -t 0 ] && [ -t 1 ]; then
        read -r -p "    Restore ~/.claude/settings.json from backup? This will overwrite recent edits. (y/N) " -n 1 REPLY
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            RESTORE=yes
        fi
    fi

    if [ "$RESTORE" = "yes" ]; then
        echo "    Restoring from $BACKUP"
        cp "$BACKUP" "$SETTINGS"
        rm "$BACKUP"
    elif command -v jq >/dev/null 2>&1; then
        # Strip any hook entries whose command exactly matches a removed symlink path.
        # We always run this so settings.json never points at deleted hooks, even
        # when a backup exists but the user (or non-interactive caller) declined to restore.
        if [ "${#REMOVED_CMDS[@]}" -gt 0 ]; then
            cmds_json=$(printf '%s\n' "${REMOVED_CMDS[@]}" | jq -R . | jq -s .)
            tmp=$(mktemp) || { echo "ERROR: mktemp failed"; exit 1; }
            jq --argjson cmds "$cmds_json" '
                if .hooks then
                    .hooks |= with_entries(
                        .value |= map(
                            .hooks |= map(select(((.command // "") | IN($cmds[])) | not))
                        ) |
                        .value |= map(select(.hooks | length > 0))
                    ) |
                    .hooks |= with_entries(select(.value | length > 0)) |
                    if (.hooks | length) == 0 then del(.hooks) else . end
                else . end
            ' "$SETTINGS" > "$tmp"
            # Write through symlinks (cat) instead of replacing the link (mv).
            cat "$tmp" > "$SETTINGS"
            rm -f "$tmp"
            echo "    cleaned via jq (${#REMOVED_CMDS[@]} entries removed)"
        else
            echo "    no entries to clean"
        fi
    else
        echo "    WARNING: jq not found, settings.json may still reference removed hooks."
    fi

    # Backup file is no longer useful once we have either restored or cleaned.
    # Leave a note rather than silently deleting so the user knows.
    if [ -f "$BACKUP" ]; then
        rm "$BACKUP"
        echo "    removed stale backup at $BACKUP"
    fi
fi

# Legacy launchd cleanup: removes any plists left over from pre-SessionStart
# installs of god-mode-os. Safe to run when no plists are present.
if [ -d "$LAUNCH_AGENTS" ]; then
    for plist in com.god-mode-os.intelligence-monitor com.god-mode-os.three-day-overview; do
        target="$LAUNCH_AGENTS/$plist.plist"
        if [ -f "$target" ]; then
            launchctl unload "$target" 2>/dev/null || true
            rm "$target"
            echo "    (legacy) removed $plist plist"
        fi
    done
fi

# Only touch Docker if the routing tier was actually installed on this machine.
ROUTING_MARKER="$GMOS_HOME/routing-installed"
if [ -f "$ROUTING_MARKER" ] && [ -f "$GMOS_REPO/router/docker-compose.yml" ]; then
    if command -v docker >/dev/null 2>&1 && docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q gmos-postgres; then
        echo "==> Stopping Postgres container"
        docker compose -f "$GMOS_REPO/router/docker-compose.yml" down
        if [ "$MODE" = "--purge" ]; then
            docker compose -f "$GMOS_REPO/router/docker-compose.yml" down -v
            echo "    volume purged"
        fi
    fi
    rm -f "$ROUTING_MARKER"
fi

if [ "$MODE" = "--purge" ]; then
    echo "==> Removing $GMOS_HOME (--purge)"
    rm -rf "$GMOS_HOME"
fi

echo ""
echo "Uninstalled. Restart Claude Code to clear hooks from active session."
[ "$MODE" != "--purge" ] && echo "Data kept at $GMOS_HOME (pass --purge to delete everything)."
