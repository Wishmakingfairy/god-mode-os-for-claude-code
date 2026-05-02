#!/bin/bash
# folder-law-reminder.sh — PreToolUse hook
# Blocks writes to forbidden locations (default: /tmp).
#
# Honors kill switch and admin override (same as install-guard.sh).
# Config: edit ~/.god-mode-os/forbidden-write-paths.txt to customize.
#
# Default forbidden paths: /tmp (files lost), ~/Downloads (clutter).

set -u

GMOS_HOME="${GMOS_HOME:-$HOME/.god-mode-os}"
KILL_SWITCH="${GMOS_KILL_SWITCH:-$HOME/.claude/.god-mode-disabled}"
CONFIG_FILE="${GMOS_FORBIDDEN_PATHS:-$GMOS_HOME/forbidden-write-paths.txt}"

[ -f "$KILL_SWITCH" ] && exit 0
[ "${GMOS_ADMIN_OVERRIDE:-}" = "1" ] && exit 0

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

command -v jq >/dev/null 2>&1 || exit 0

TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Load forbidden paths
declare -a FORBIDDEN_PATHS
if [ -f "$CONFIG_FILE" ]; then
    while IFS= read -r line; do
        line="${line%%#*}"
        line="${line## }"; line="${line%% }"
        [ -z "$line" ] && continue
        line="${line/#\~/$HOME}"
        FORBIDDEN_PATHS+=("$line")
    done < "$CONFIG_FILE"
else
    FORBIDDEN_PATHS=(
        "/tmp"
        "$HOME/Downloads"
    )
fi

is_forbidden_target() {
    local target="$1"
    for path in "${FORBIDDEN_PATHS[@]}"; do
        if [[ "$target" == "$path"* ]]; then
            return 0
        fi
    done
    return 1
}

block_msg() {
    local target="$1"
    >&2 echo "FOLDER LAW BLOCKED: write to forbidden path: $target"
    >&2 echo "Forbidden paths: ${FORBIDDEN_PATHS[*]}"
    >&2 echo "Edit $CONFIG_FILE to change, or run with GMOS_ADMIN_OVERRIDE=1."
}

case "$TOOL" in
    Write|Edit|MultiEdit)
        FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
        if [ -n "$FILE_PATH" ] && is_forbidden_target "$FILE_PATH"; then
            block_msg "$FILE_PATH"
            exit 2
        fi
        ;;
    Bash)
        CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
        [ -z "$CMD" ] && exit 0
        for path in "${FORBIDDEN_PATHS[@]}"; do
            if echo "$CMD" | grep -qE "(>|>>|tee|mkdir|touch)\\s+$path" || \
               echo "$CMD" | grep -qE "\\b(cp|mv)\\b[^#]*\\s$path/?(\\s|\$)"; then
                block_msg "$path (in command: $CMD)"
                exit 2
            fi
        done
        ;;
esac

exit 0
