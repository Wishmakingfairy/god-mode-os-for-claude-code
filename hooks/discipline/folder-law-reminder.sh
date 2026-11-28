#!/bin/bash
# folder-law-reminder.sh : PreToolUse hook
# Speaks up when the agent writes to a place where files get lost or pile up.
# Default paths: /tmp (cleared on reboot) and ~/Downloads (clutter).
#
# Default mode is WARN: the write goes through and the agent is told to pick a durable place.
# Set GMOS_FOLDER_LAW=block to stop the write instead.
#
# Honors kill switch and admin override (same as install-guard.sh).
# Config: edit ~/.god-mode-os/forbidden-write-paths.txt to customize.

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

# On macOS /tmp and /var are links into /private. Both spellings mean the same folder.
plain_path() {
    local p="${1%/}"
    case "$p" in /private/tmp|/private/tmp/*|/private/var|/private/var/*) p="${p#/private}" ;; esac
    printf '%s' "$p"
}

# A target matches when it IS a listed folder or sits inside one. "/tmpl" does not match "/tmp".
is_forbidden_target() {
    local target path
    target=$(plain_path "$1")
    for path in "${FORBIDDEN_PATHS[@]}"; do
        path=$(plain_path "$path")
        [ -z "$path" ] && continue
        if [ "$target" = "$path" ] || [[ "$target" == "$path/"* ]]; then
            return 0
        fi
    done
    return 1
}

MODE="${GMOS_FOLDER_LAW:-warn}"

# Either blocks (exit 2 + stderr) or warns (exit 0 + context for the agent), depending on MODE.
flag() {
    local target="$1"
    if [ "$MODE" = "block" ]; then
        >&2 echo "FOLDER LAW BLOCKED: write to forbidden path: $target"
        >&2 echo "Forbidden paths: ${FORBIDDEN_PATHS[*]}"
        >&2 echo "Edit $CONFIG_FILE to change, or pick another folder."
        exit 2
    fi
    jq -cn --arg t "$target" --arg p "${FORBIDDEN_PATHS[*]}" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:("Folder note: this writes to " + $t + ", a place where files get lost or pile up (" + $p + "). If the file should be kept, write it inside the project instead.")}}'
    exit 0
}

case "$TOOL" in
    Write|Edit|MultiEdit)
        FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
        if [ -n "$FILE_PATH" ] && is_forbidden_target "$FILE_PATH"; then
            flag "$FILE_PATH"
        fi
        ;;
    Bash)
        CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
        [ -z "$CMD" ] && exit 0
        for path in "${FORBIDDEN_PATHS[@]}"; do
            if echo "$CMD" | grep -qE "(>|>>|tee|mkdir|touch)\\s+$path" || \
               echo "$CMD" | grep -qE "\\b(cp|mv)\\b[^#]*\\s$path/?(\\s|\$)"; then
                flag "$path"
            fi
        done
        ;;
esac

exit 0
