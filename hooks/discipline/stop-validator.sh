#!/bin/bash
# stop-validator.sh — Stop event hook
# Inspects the assistant's last response for objective rule violations.
#
# Built-in checks (toggle each via env var, all on by default):
#   GMOS_CHECK_EM_DASH=1         em-dash hard ban (style)
#   GMOS_CHECK_TOOL_USE=1        no claims about files without reading them first
#   GMOS_CHECK_CITATIONS=1       statistics and version claims need a source
#   GMOS_CHECK_CONSISTENCY=1     contradiction with prior turn (Ollama)
#   GMOS_CHECK_DODGE=1           capability denial / dodge (Ollama)
#
# Honors kill switch and admin override.
# Exit 0 = pass. Exit 2 + stderr = block.

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
set -u

GMOS_HOME="${GMOS_HOME:-$HOME/.god-mode-os}"
KILL_SWITCH="${GMOS_KILL_SWITCH:-$HOME/.claude/.god-mode-disabled}"
LOG_FILE="${GMOS_CORRECTION_LOG:-$GMOS_HOME/correction-log.md}"
PENDING_LOG="${GMOS_PENDING_LOG:-$GMOS_HOME/correction-log-pending.md}"

[ -f "$KILL_SWITCH" ] && exit 0
[ "${GMOS_ADMIN_OVERRIDE:-}" = "1" ] && exit 0

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Loop guard
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
[ "$STOP_ACTIVE" = "true" ] && exit 0

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
[ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ] && exit 0

# Extract the last assistant text content
LAST_MSG=$(jq -rs '[.[] | select(.message.role? == "assistant" or .role? == "assistant")] | last | (.message.content? // .content? // []) | if type == "array" then map(select(.type? == "text") | .text) | join("\n") else tostring end' "$TRANSCRIPT_PATH" 2>/dev/null)

[ -z "$LAST_MSG" ] && exit 0
[ "$LAST_MSG" = "null" ] && exit 0

mkdir -p "$GMOS_HOME" 2>/dev/null

log_block() {
    local reason="$1"
    local snippet
    snippet=$(echo "$LAST_MSG" | head -c 200 | tr '\n' ' ')
    echo "- [$(date +%Y-%m-%d)] BLOCK: $reason | Snippet: ${snippet}..." >> "$LOG_FILE"
}

log_pending() {
    local conf="$1"
    local reason="$2"
    local snippet
    snippet=$(echo "$LAST_MSG" | head -c 200 | tr '\n' ' ')
    echo "- [$(date +%Y-%m-%d)] PENDING (conf $conf): $reason | Snippet: ${snippet}..." >> "$PENDING_LOG"
}

emit_block() {
    local reason="$1"
    >&2 echo "STOP VALIDATOR BLOCK: $reason"
    >&2 echo ""
    >&2 echo "Your previous response violated a rule. Rewrite to fix."
    >&2 echo "If this is a false positive, ask the user to confirm and override."
    exit 2
}

# === Check: em dash ===
if [ "${GMOS_CHECK_EM_DASH:-1}" = "1" ]; then
    if echo "$LAST_MSG" | grep -q '—'; then
        log_block "em dash in response"
        emit_block "Em dash detected. Rewrite using periods, commas, colons, or semicolons."
    fi
fi

# === Check: tool use before factual claims about files ===
if [ "${GMOS_CHECK_TOOL_USE:-1}" = "1" ]; then
    RESPONSE_PATHS=$(echo "$LAST_MSG" | grep -oE '(~|/)[A-Za-z0-9._/-]+\.(sh|md|json|js|ts|py|tsx|jsx|html|css|yaml|yml|toml|txt|conf)' | sort -u | head -5)
    if [ -n "$RESPONSE_PATHS" ]; then
        RECENT_TOOL_USES=$(tail -30 "$TRANSCRIPT_PATH" 2>/dev/null | jq -r '.. | objects | select(.type? == "tool_use") | (.input.file_path // .input.pattern // .input.command // empty)' 2>/dev/null)
        while IFS= read -r path; do
            [ -z "$path" ] && continue
            path_base=$(basename "$path")
            if ! echo "$RECENT_TOOL_USES" | grep -q "$path_base"; then
                log_block "tool-use-before-claim: $path"
                emit_block "You made a claim about $path without reading or inspecting it first. Use Read, Grep, or Bash on this file BEFORE making claims about its contents."
            fi
        done <<< "$RESPONSE_PATHS"
    fi
fi

# === Check: citation requirement for statistics ===
if [ "${GMOS_CHECK_CITATIONS:-1}" = "1" ]; then
    if echo "$LAST_MSG" | grep -qE '([0-9]+%|[0-9]+ out of [0-9]+|studies show|research shows|version [0-9]+\.[0-9]+.*(supports|added|deprecated|removed))'; then
        if ! echo "$LAST_MSG" | grep -qE '(https?://|\.(sh|md|json|js|ts|py)(:[0-9]+)?|`[^`]+`)'; then
            log_block "citation-required: factual claim without source marker"
            emit_block "You made a statistic or version claim without a source. Add a URL, file path, or command output, or remove the unsourced claim."
        fi
    fi
fi

OLLAMA_BIN="${GMOS_OLLAMA:-/opt/homebrew/bin/ollama}"
OLLAMA_MODEL="${GMOS_OLLAMA_MODEL:-llama3.2}"

# === Check: contextual consistency (Ollama) ===
if [ "${GMOS_CHECK_CONSISTENCY:-1}" = "1" ] && [ ${#LAST_MSG} -gt 300 ] && [ -x "$OLLAMA_BIN" ]; then
    PRIOR_CONTEXT=$(tail -20 "$TRANSCRIPT_PATH" 2>/dev/null | sed '$d' | jq -r '.message.content[]? | select(.type? == "text") | .text' 2>/dev/null | head -c 3000)
    if [ -n "$PRIOR_CONTEXT" ]; then
        CONSISTENCY_PROMPT="Does the NEW statement contradict a factual claim in the PRIOR context? Ignore style differences and updated plans (those are not contradictions). Only a hard factual contradiction counts.

Reply with ONLY a single digit: 1 if contradicts, 0 if consistent.

PRIOR:
$PRIOR_CONTEXT

NEW:
$(echo "$LAST_MSG" | head -c 2000)

Your answer (single digit only):"
        CONS_OUT=$(echo "$CONSISTENCY_PROMPT" | timeout 10 "$OLLAMA_BIN" run "$OLLAMA_MODEL" 2>/dev/null | tr -d '[:space:]' | head -c 1)
        if [ "$CONS_OUT" = "1" ]; then
            log_block "contextual-consistency: contradicts earlier turn"
            emit_block "Detected contradiction with earlier statement. Either correct the contradiction or explicitly acknowledge you changed position."
        fi
    fi
fi

# === Check: capability denial / dodge (Ollama) ===
if [ "${GMOS_CHECK_DODGE:-1}" = "1" ] && [ -x "$OLLAMA_BIN" ]; then
    OLLAMA_PROMPT="Check if a Claude Code response is dodging or claiming false inability. Claude has these tools available by default: Bash, Read, Write, Edit, Grep, Glob, WebSearch, WebFetch, plus user-installed MCP servers and skills.

Respond with EXACTLY one line: VERDICT|CONFIDENCE|REASON
- VERDICT = DODGE (Claude refused or claimed inability to use a tool it has) or PASS (legitimate response)
- CONFIDENCE = integer 0-100
- REASON = brief

Response (first 1500 chars):
$(echo "$LAST_MSG" | head -c 1500)"

    OLLAMA_OUT=$(echo "$OLLAMA_PROMPT" | timeout 8 "$OLLAMA_BIN" run "$OLLAMA_MODEL" 2>/dev/null | head -1)

    if [ -n "$OLLAMA_OUT" ]; then
        VERDICT=$(echo "$OLLAMA_OUT" | cut -d'|' -f1 | tr -d ' ')
        CONF=$(echo "$OLLAMA_OUT" | cut -d'|' -f2 | grep -oE '[0-9]+' | head -1)
        REASON=$(echo "$OLLAMA_OUT" | cut -d'|' -f3- | head -c 200)

        if [ "$VERDICT" = "DODGE" ] && [ -n "$CONF" ]; then
            if [ "$CONF" -ge 85 ]; then
                log_block "Ollama DODGE conf=$CONF: $REASON"
                emit_block "Detected capability denial (confidence $CONF): $REASON"
            elif [ "$CONF" -ge 70 ]; then
                log_pending "$CONF" "$REASON"
            fi
        fi
    fi
fi

exit 0
