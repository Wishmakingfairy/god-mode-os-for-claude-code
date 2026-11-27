#!/bin/bash
# stop-validator.sh : Stop event hook
# Inspects the assistant's last response for objective rule violations.
#
# Built-in checks (toggle each via env var, on by default unless marked):
# Only the first attempt of a reply is checked: after a block, the rewrite goes through
# unchecked (stop_hook_active), so the hook can never loop.
#   GMOS_CHECK_EM_DASH=1         em-dash hard ban (style)
#   GMOS_CHECK_SLOP=1            AI-slop filler words (style)
#   GMOS_CHECK_SYCOPHANCY=1      sycophantic openers (style)
#   GMOS_CHECK_TOOL_USE=1        no claims about files without reading them first
#   GMOS_CHECK_CITATIONS=1       statistics and version claims need a source
#   GMOS_CHECK_VERIFY_CLAIM=0    "tests pass" / "build succeeds" needs a command run in this turn. OFF by default.
#   GMOS_CHECK_CONSISTENCY=1     contradiction with prior turn (Ollama). Records only, never blocks.
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
EVENT_LOG="${GMOS_STOP_LOG:-$GMOS_HOME/stop-validator.log}"

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

# The final reply. Claude Code hands it over in the hook input (last_assistant_message); at that
# moment it is often not written to the transcript yet. The transcript is the fallback.
LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null)
[ -z "$LAST_MSG" ] && LAST_MSG=$(jq -rs '[.[] | select(.message.role? == "assistant" or .role? == "assistant")] | last | (.message.content? // .content? // []) | if type == "array" then map(select(.type? == "text") | .text) | join("\n") else tostring end' "$TRANSCRIPT_PATH" 2>/dev/null)

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

# A check that only records and never stops the reply. Second argument: earlier text to keep beside it.
log_only() {
    local reason="$1"
    local prior snippet
    prior=$(printf '%s' "$2" | tail -c 300 | tr '\n' ' ')
    snippet=$(echo "$LAST_MSG" | head -c 200 | tr '\n' ' ')
    echo "- [$(date +%Y-%m-%d)] LOG-ONLY: $reason | Prior: ...${prior} | Snippet: ${snippet}..." >> "$EVENT_LOG"
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
    EM_DASH=$(printf '\342\200\224')
    if echo "$LAST_MSG" | grep -q "$EM_DASH"; then
        log_block "em dash in response"
        emit_block "Em dash detected. Rewrite using periods, commas, colons, or semicolons."
    fi
fi

# === Check: AI-slop filler words ===
# "robust" and "scalable" are not on the list: they are ordinary technical words.
if [ "${GMOS_CHECK_SLOP:-1}" = "1" ]; then
    SLOP_RE='\b(delve|leverage|utilize|seamlessly|unlock|game-changer|game changer|elevate|cutting-edge|cutting edge|groundbreaking|revolutionary|transformative|synergy|holistic|paradigm)\b'
    if echo "$LAST_MSG" | grep -qiE "$SLOP_RE"; then
        WORD=$(echo "$LAST_MSG" | grep -oiE "$SLOP_RE" | head -1)
        log_block "AI-slop word: $WORD"
        emit_block "AI-slop word detected: \"$WORD\". Rewrite without filler/marketing words."
    fi
fi

# === Check: sycophantic openers ===
if [ "${GMOS_CHECK_SYCOPHANCY:-1}" = "1" ]; then
    FIRST_LINE=$(echo "$LAST_MSG" | sed '/^[[:space:]]*$/d' | head -1)
    if echo "$FIRST_LINE" | grep -qiE '^(great( question)?!?|certainly!?|of course!?|absolutely!?|sure!?|happy to (help|assist)|glad to|excellent!?|perfect!?|wonderful!?|fantastic!?|awesome!?)[[:space:]]*$'; then
        log_block "sycophantic opener: $FIRST_LINE"
        emit_block "Sycophantic opener detected: \"$FIRST_LINE\". Do not open with affirmations. Lead with content."
    fi
fi

# === Check: tool use before factual claims about files ===
# Fires when the reply names a concrete file path that no tool call in this chat touched
# and the user never typed. Not counted as file claims: web addresses, text inside straight
# double quotes (examples), and paths with three dots (placeholders).
if [ "${GMOS_CHECK_TOOL_USE:-1}" = "1" ]; then
    CLAIM_TEXT=$(printf '%s\n' "$LAST_MSG" | sed -E 's#https?://[^[:space:])>"`]+##g; s/"[^"]*"//g')
    RESPONSE_PATHS=$(echo "$CLAIM_TEXT" | grep -oE '(~|[A-Za-z0-9._-]*)/[A-Za-z0-9._/-]+\.(sh|md|json|js|ts|py|tsx|jsx|html|css|yaml|yml|toml|txt|conf)' | grep -vF -e '...' | sort -u | head -5)
    if [ -n "$RESPONSE_PATHS" ]; then
        # Known paths: every tool call in this chat (file path, folder, pattern, command) plus
        # the text the user typed. The hook's own "Stop hook feedback" messages are left out,
        # so a block cannot whitelist its own path. Whole transcript up to 50 MB, else the
        # last 4000 lines. A broken transcript line is skipped, not fatal.
        KNOWN_FILTER='fromjson? | select(.message? != null) | .message as $m | ($m.content // empty) | if type == "string" then (if $m.role == "user" then . else empty end) elif type == "array" then (.[] | if .type? == "tool_use" then ((.input // {}) | (.file_path, .path, .pattern, .command, .notebook_path) | strings) elif (.type? == "text" and $m.role == "user") then .text else empty end) else empty end | select(startswith("Stop hook feedback") | not)'
        TRANSCRIPT_BYTES=$(wc -c < "$TRANSCRIPT_PATH" 2>/dev/null | tr -d ' ')
        if [ "${TRANSCRIPT_BYTES:-0}" -le 52428800 ]; then
            KNOWN_PATHS=$(jq -rR "$KNOWN_FILTER" "$TRANSCRIPT_PATH" 2>/dev/null)
        else
            KNOWN_PATHS=$(tail -n 4000 "$TRANSCRIPT_PATH" 2>/dev/null | jq -rR "$KNOWN_FILTER" 2>/dev/null)
        fi
        while IFS= read -r path; do
            [ -z "$path" ] && continue
            path_base=$(basename "$path")
            if ! echo "$KNOWN_PATHS" | grep -qF -e "$path_base"; then
                log_block "tool-use-before-claim: $path"
                emit_block "You made a claim about $path without reading or inspecting it first. Use Read, Grep, or Bash on this file BEFORE making claims about its contents."
            fi
        done <<< "$RESPONSE_PATHS"
    fi
fi

# === Check: citation requirement for statistics ===
# Fires on a statistic or version claim with no source marker in the reply, unless a tool
# result holding a number arrived in the current turn (then the number has a visible origin).
if [ "${GMOS_CHECK_CITATIONS:-1}" = "1" ]; then
    if echo "$LAST_MSG" | grep -qiE '([0-9]+%|[0-9]+ out of [0-9]+|studies show|research shows|version [0-9]+\.[0-9]+.*(supports|added|deprecated|removed))'; then
        if ! echo "$LAST_MSG" | grep -qE '(https?://|\.(sh|md|json|js|ts|py)(:[0-9]+)?|`[^`]+`)'; then
            # The current turn is everything after the last message the user typed.
            TURN_FILTER='split("\n") | map(fromjson? | select(.message? != null) | .message) as $m | ([ $m | to_entries[] | select(.value.role == "user" and (.value.content | if type == "string" then (startswith("Stop hook feedback") | not) elif type == "array" then ((any(.[]; .type? == "tool_result") | not) and (any(.[]; (.type? == "text") and ((.text // "") | startswith("Stop hook feedback"))) | not)) else false end)) | .key ] | last // 0) as $i | [ $m[$i:][] | .content | arrays | .[] | select(.type? == "tool_result") | (.content | tostring) | select(test("[0-9]")) ] | length'
            TURN_TOOL_NUM=$(tail -n 400 "$TRANSCRIPT_PATH" 2>/dev/null | jq -sR "$TURN_FILTER" 2>/dev/null)
            if [ "${TURN_TOOL_NUM:-0}" = "0" ]; then
                log_block "citation-required: factual claim without source marker"
                emit_block "You made a statistic or version claim without a source. Add a URL, file path, or command output, or remove the unsourced claim."
            fi
        fi
    fi
fi

# === Check: "tests pass" / "build succeeds" / "I ran it" with nothing run in this turn ===
# Off by default: set GMOS_CHECK_VERIFY_CLAIM=1 to switch it on.
# Fires when a sentence ends by stating that tests, a build or lint passed, or says the agent
# ran the tests or the build, while the current turn holds no tool call other than viewing and
# editing files. Not counted as a claim: a sentence with a hedge or a negation (should, not,
# if, earlier, a question), text in quotes or backticks, and a repeat of what the user said.
# It reads words, not meaning: a claim phrased another way gets through.
if [ "${GMOS_CHECK_VERIFY_CLAIM:-0}" = "1" ]; then
    VERIFY_RE='\b(tests?|test suite|suite|specs?|build|lint|linter|type ?check|typecheck)( (is|are|all|now|still|again|has|have|run))*[[:space:]]+(pass|passes|passed|passing|succeeds|succeeded|green|clean)( (now|again|locally|cleanly|successfully))?[[:space:]]*$|\bI( have)? (ran|re-?ran|run|executed) (the |all |all the |every )?(full |whole |entire )?(tests?|test suite|suite|build|linter|lint|specs?)\b'
    HEDGE_RE='\b(not|never|should|would|could|might|may|if|once|when|whether|until|unless|will|ensure|make sure|please|earlier|previously|before|cannot|need to|needs to|expect|confirm|says|said|report|output|pasted|according)\b|n'"'"'t\b|\?'
    VERIFY_HITS=$(printf '%s\n' "$LAST_MSG" | sed -E 's/"[^"]*"//g; s/`[^`]*`//g' | tr '.!;' '\n\n\n' | grep -iE "$VERIFY_RE" | grep -viE "$HEDGE_RE" | head -1)
    if [ -n "$VERIFY_HITS" ]; then
        # First line: how many tool calls in the current turn could have run something.
        # Rest: what the user typed to start the turn.
        VERIFY_FILTER='split("\n") | map(fromjson? | select(.message? != null) | .message) as $m | ([ $m | to_entries[] | select(.value.role == "user" and (.value.content | if type == "string" then (startswith("Stop hook feedback") | not) elif type == "array" then ((any(.[]; .type? == "tool_result") | not) and (any(.[]; (.type? == "text") and ((.text // "") | startswith("Stop hook feedback"))) | not)) else false end)) | .key ] | last // 0) as $i | ([ $m[$i:][] | .content | arrays | .[] | select(.type? == "tool_use") | (.name // "") | select(test("^(Read|Edit|Write|MultiEdit|NotebookEdit|Glob|Grep|TodoWrite|TaskCreate|TaskUpdate|AskUserQuestion)$") | not) ] | length) as $n | ($m[$i] // {} | if .role == "user" then (.content | if type == "string" then . elif type == "array" then (map(select(.type? == "text") | .text) | join(" ")) else "" end) else "" end) as $u | "\($n)\n\($u)"'
        VERIFY_OUT=$(tail -n 400 "$TRANSCRIPT_PATH" 2>/dev/null | jq -rsR "$VERIFY_FILTER" 2>/dev/null)
        VERIFY_RAN=$(printf '%s\n' "$VERIFY_OUT" | head -1)
        VERIFY_USER=$(printf '%s\n' "$VERIFY_OUT" | tail -n +2)
        if [ "${VERIFY_RAN:-1}" = "0" ] && ! printf '%s' "$VERIFY_USER" | grep -qiE "$VERIFY_RE"; then
            VERIFY_SNIP=$(printf '%s' "$VERIFY_HITS" | sed -E 's/^[[:space:]]+//' | head -c 120)
            log_block "verify-claim: said it passed or ran with nothing run this turn: $VERIFY_SNIP"
            emit_block "You wrote \"$VERIFY_SNIP\" but ran no command in this turn. Run the tests or the build now and report what the output says, or say plainly that it was not run."
        fi
    fi
fi

OLLAMA_BIN="${GMOS_OLLAMA:-/opt/homebrew/bin/ollama}"
OLLAMA_MODEL="${GMOS_OLLAMA_MODEL:-llama3.2}"

# === Check: contextual consistency (Ollama). Records only, never blocks. ===
# In the author's own use (his own count, not published), 0 of 15 sampled blocks from this check were a real contradiction,
# so it no longer stops a reply. A hit is written to the log with the earlier text beside it.
# Replies shaped like a summary (a table, or 3 or more status lines) are skipped: they restate
# earlier work and a small local model reads the restatement as a contradiction.
if [ "${GMOS_CHECK_CONSISTENCY:-1}" = "1" ] && [ ${#LAST_MSG} -gt 300 ] && [ -x "$OLLAMA_BIN" ]; then
    PRIOR_CONTEXT=$(tail -20 "$TRANSCRIPT_PATH" 2>/dev/null | sed '$d' | jq -r '.message.content[]? | select(.type? == "text") | .text' 2>/dev/null | head -c 3000)
    SKIP_CONS=0
    if printf '%s' "$LAST_MSG" | grep -qE '\|[[:space:]]*:?-{2,}'; then SKIP_CONS=1; fi
    if [ "$(printf '%s' "$LAST_MSG" | grep -icE 'verified|done|complete|backed up')" -ge 3 ]; then SKIP_CONS=1; fi
    if [ -n "$PRIOR_CONTEXT" ] && [ "$SKIP_CONS" = "0" ]; then
        CONSISTENCY_PROMPT="Does the NEW statement contradict a factual claim in the PRIOR context? Ignore style differences, updated plans, and a changed mind (those are not contradictions). Only a hard factual contradiction counts.

Reply with ONLY a single digit: 1 if contradicts, 0 if consistent.

PRIOR:
$PRIOR_CONTEXT

NEW:
$(echo "$LAST_MSG" | head -c 2000)

Your answer (single digit only):"
        # Majority vote across 3 samples. Stop early once the result is settled.
        votes=0; zeros=0
        for _ in 1 2 3; do
            CONS_OUT=$(echo "$CONSISTENCY_PROMPT" | timeout 10 "$OLLAMA_BIN" run "$OLLAMA_MODEL" 2>/dev/null | tr -d '[:space:]' | head -c 1)
            if [ "$CONS_OUT" = "1" ]; then votes=$((votes + 1)); else zeros=$((zeros + 1)); fi
            [ "$votes" -ge 2 ] && break
            [ "$zeros" -ge 2 ] && break
        done
        if [ "$votes" -ge 2 ]; then
            log_only "contextual-consistency: possible contradiction with an earlier turn ($votes of 3)" "$PRIOR_CONTEXT"
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
