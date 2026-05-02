#!/bin/bash
# install-guard.sh — PreToolUse hook
# Blocks tool calls writing to / moving / deleting Claude Code config paths.
#
# Honors kill switch at ~/.claude/.god-mode-disabled
# Honors GMOS_ADMIN_OVERRIDE=1 env var for explicit one-time approval.
#
# Exit 0 = allow. Exit 2 + stderr = block (Claude Code shows stderr to the model).
#
# Config: edit ~/.god-mode-os/protected-paths.txt to customize blocked paths.
# Defaults protect ~/.claude/{settings.json,hooks/,skills/,plugins/,commands/}

set -u

GMOS_HOME="${GMOS_HOME:-$HOME/.god-mode-os}"
KILL_SWITCH="${GMOS_KILL_SWITCH:-$HOME/.claude/.god-mode-disabled}"
EVENT_LOG="${GMOS_EVENT_LOG:-$GMOS_HOME/events.jsonl}"
CONFIG_FILE="${GMOS_PROTECTED_PATHS:-$GMOS_HOME/protected-paths.txt}"

# 1. Kill switch
[ -f "$KILL_SWITCH" ] && exit 0

# 2. Admin override
[ "${GMOS_ADMIN_OVERRIDE:-}" = "1" ] && exit 0

# 3. Read JSON input from stdin
INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

# Need jq; if missing, fail-open (do not break sessions)
command -v jq >/dev/null 2>&1 || exit 0

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ -z "$TOOL_NAME" ] && exit 0

# 4. Load protected paths (config file or sensible defaults)
declare -a PROTECTED_PATHS
if [ -f "$CONFIG_FILE" ]; then
    while IFS= read -r line; do
        line="${line%%#*}"  # strip comments
        line="${line## }"; line="${line%% }"  # trim
        [ -z "$line" ] && continue
        # Expand ~ and $HOME
        line="${line/#\~/$HOME}"
        line="${line//\$HOME/$HOME}"
        PROTECTED_PATHS+=("$line")
    done < "$CONFIG_FILE"
else
    PROTECTED_PATHS=(
        "$HOME/.claude.json"
        "$HOME/.claude/settings.json"
        "$HOME/.claude/settings.local.json"
        "$HOME/.claude/hooks/"
        "$HOME/.claude/skills/"
        "$HOME/.claude/plugins/"
        "$HOME/.claude/commands/"
    )
fi

is_protected_path() {
    local target="$1"
    for path in "${PROTECTED_PATHS[@]}"; do
        if [[ "$target" == *"$path"* ]]; then
            return 0
        fi
    done
    if [[ "$target" == *"CLAUDE.md"* ]]; then
        return 0
    fi
    return 1
}

block() {
    local reason="$1"
    if [ -d "$GMOS_HOME" ] || mkdir -p "$GMOS_HOME" 2>/dev/null; then
        echo "{\"ts\":$(date +%s),\"hook\":\"install-guard\",\"event\":\"block\",\"detail\":$(printf '%s' "$reason" | jq -Rs .)}" >> "$EVENT_LOG" 2>/dev/null
    fi
    >&2 echo "INSTALL/CONFIG GUARD BLOCK: $reason"
    >&2 echo ""
    >&2 echo "This hook prevents accidental writes to Claude Code config paths."
    >&2 echo "To proceed legitimately:"
    >&2 echo "  1. Confirm the change is intentional."
    >&2 echo "  2. Re-run with GMOS_ADMIN_OVERRIDE=1 set, OR disable via:"
    >&2 echo "     touch $KILL_SWITCH    # kill switch on"
    >&2 echo "     rm $KILL_SWITCH       # kill switch off"
    exit 2
}

case "$TOOL_NAME" in
    Edit|Write|MultiEdit|NotebookEdit)
        FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
        if [ -n "$FILE_PATH" ] && is_protected_path "$FILE_PATH"; then
            block "$TOOL_NAME on protected path: $FILE_PATH"
        fi
        ;;
    Bash)
        CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
        [ -z "$CMD" ] && exit 0

        if echo "$CMD" | grep -qE '(claude[[:space:]]+mcp[[:space:]]+add|claude[[:space:]]+plugin[[:space:]]+install)'; then
            block "Claude Code install command: $CMD"
        fi

        if echo "$CMD" | grep -qE 'git[[:space:]]+clone.*\.claude/(skills|plugins|hooks|commands)'; then
            block "git clone into protected path: $CMD"
        fi

        WRITE_VERB_RE='(>>?[[:space:]]|>$|tee[[:space:]]|cp[[:space:]]|mv[[:space:]]|rm[[:space:]]|sed[[:space:]]+-i|install[[:space:]]|ln[[:space:]]|rsync[[:space:]]|printf[[:space:]].*>)'
        if echo "$CMD" | grep -qE "$WRITE_VERB_RE"; then
            for path in "${PROTECTED_PATHS[@]}"; do
                if [[ "$CMD" == *"$path"* ]]; then
                    block "write/move/delete targeting protected path in: $CMD"
                fi
            done
            if [[ "$CMD" == *"CLAUDE.md"* ]]; then
                block "write/move/delete targeting CLAUDE.md in: $CMD"
            fi
        fi
        ;;
esac

exit 0
