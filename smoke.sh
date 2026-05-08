#!/bin/bash
# smoke.sh — runs every load-bearing claim in the README against the
# actual code on this machine and prints a plain-English receipt.
#
# Don't trust the README? Run this. It tells you which claims are true
# and shows you exactly how each one was tested. Hard-fails (exit 1)
# if any behavioural claim is false. Soft-warns (exit 0) if a timing
# claim is slower than advertised on this machine.
#
#   bash smoke.sh           # plain summary
#   bash smoke.sh -v        # verbose: include the "how" line for each check
#   bash smoke.sh --help    # this help
#
# Pure bash + jq + python3. No bats, shellspec, ruby, or other deps.

set -u

# ─── argument parsing ───────────────────────────────────────────────
VERBOSE=0
for arg in "$@"; do
    case "$arg" in
        -v|--verbose) VERBOSE=1 ;;
        -h|--help)
            sed -n '2,15p' "$0" | sed 's/^# //; s/^#//'
            exit 0 ;;
        *) echo "unknown arg: $arg (try --help)" >&2; exit 2 ;;
    esac
done

# ─── isolation: NEVER touch the user's real ~/.god-mode-os ──────────
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_HOME=$(mktemp -d) || { echo "ERROR: mktemp failed (disk full?)"; exit 1; }
TEST_GMOS=$(mktemp -d) || { echo "ERROR: mktemp failed"; exit 1; }
TRANS_FILE=""

cleanup() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME" 2>/dev/null
    [ -n "${TEST_GMOS:-}" ] && rm -rf "$TEST_GMOS" 2>/dev/null
    [ -n "${TRANS_FILE:-}" ] && rm -f "$TRANS_FILE" 2>/dev/null
}
trap cleanup EXIT INT TERM

# ─── pre-flight ─────────────────────────────────────────────────────
command -v jq >/dev/null 2>&1 || { echo "ERROR: smoke.sh needs jq. brew install jq"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: smoke.sh needs python3"; exit 1; }

# ─── reporting helpers ──────────────────────────────────────────────
PASS=0; HARD_FAIL=0; SOFT_WARN=0
ok() {
    PASS=$((PASS + 1))
    echo "  PASS  $1"
    if [ "$VERBOSE" = "1" ] && [ -n "${2:-}" ]; then
        echo "        how: $2"
    fi
    return 0
}
warn() {
    SOFT_WARN=$((SOFT_WARN + 1))
    echo "  WARN  $1"
    if [ "$VERBOSE" = "1" ] && [ -n "${2:-}" ]; then
        echo "        why: $2"
    fi
    return 0
}
no() {
    HARD_FAIL=$((HARD_FAIL + 1))
    echo "  FAIL  $1"
    if [ -n "${2:-}" ]; then
        echo "        why: $2"
    fi
    return 0
}

# Run a process in test isolation: HOME + GMOS_HOME both redirected.
gmos_run() {
    HOME="$TEST_HOME" GMOS_HOME="$TEST_GMOS" "$@"
}

echo "============================================================"
echo "  god-mode-os smoke test"
echo "============================================================"
echo ""
echo "Tests every load-bearing README claim against the real code."
echo "PASS = verified true. WARN = soft (timing, machine-dependent)."
echo "FAIL = false (would block ship)."
[ "$VERBOSE" = "0" ] && echo "Pass -v / --verbose to see how each check was performed."
echo ""

# ════════════════════════════════════════════════════════════════════
echo "[hard] CLAIM 1: 'Default install only requires jq + python3'"
DEPS=$(grep -E "^command -v (jq|python3)" "$REPO/install.sh" | wc -l | tr -d ' ')
[ "$DEPS" = "2" ] \
    && ok "install.sh hard-requires exactly 2 deps: jq + python3" \
          "grep'd 'command -v jq|python3' in install.sh, found $DEPS lines" \
    || no "expected 2 hard deps, install.sh declares $DEPS"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "[hard] CLAIM 2: 'Default install creates 5 hooks + 4 settings.json entries'"
gmos_run "$REPO/install.sh" discipline >/dev/null 2>&1
HOOKS=$(find "$TEST_HOME/.claude/hooks" -type l 2>/dev/null | wc -l | tr -d ' ')
[ "$HOOKS" = "5" ] \
    && ok "5 hook symlinks created" \
          "counted symlinks in test HOME's .claude/hooks/" \
    || no "expected 5 hooks, found $HOOKS"

ENTRIES=$(jq '[.hooks[][].hooks[]] | length' "$TEST_HOME/.claude/settings.json" 2>/dev/null)
[ "$ENTRIES" = "4" ] \
    && ok "4 hook entries in settings.json (2 PreToolUse + 2 Stop)" \
          "ran ./install.sh, counted entries via jq" \
    || no "expected 4 entries, found $ENTRIES"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "[soft] CLAIM 3: 'Install completes in ~60 seconds'"
gmos_run "$REPO/uninstall.sh" --purge </dev/null >/dev/null 2>&1
START=$(python3 -c 'import time;print(int(time.time()*1000))')
gmos_run "$REPO/install.sh" discipline >/dev/null 2>&1
END=$(python3 -c 'import time;print(int(time.time()*1000))')
ELAPSED_MS=$((END - START))
if [ "$ELAPSED_MS" -lt 60000 ]; then
    ok "install completed in ${ELAPSED_MS}ms (claim: <60000ms)" \
       "timed a from-scratch ./install.sh on a clean test HOME"
else
    warn "install took ${ELAPSED_MS}ms (claim: <60000ms). Slow disk?" \
         "soft warning; behavioural claims still pass"
fi

# ════════════════════════════════════════════════════════════════════
echo ""
echo "[hard] CLAIM 4: 'stop-validator blocks claims about files without recent Read'"
TRANS_FILE=$(mktemp).jsonl
DASH=$(printf '\xe2\x80\x94')
cat > "$TRANS_FILE" <<EOF
{"type":"user","message":{"role":"user","content":"fix it"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Done ${DASH} all 10 of 10 tests pass in /tmp/fakefile.ts"}]}}
EOF
EXIT=$(echo "{\"hook_event_name\":\"Stop\",\"transcript_path\":\"$TRANS_FILE\",\"stop_hook_active\":false}" \
    | env -u GMOS_ADMIN_OVERRIDE HOME="$TEST_HOME" GMOS_HOME="$TEST_GMOS" \
        bash "$TEST_HOME/.claude/hooks/stop-validator.sh" >/dev/null 2>&1; echo $?)
[ "$EXIT" = "2" ] \
    && ok "stop-validator BLOCKED the false claim (exit 2)" \
          "fed a fake assistant turn that claims 'all tests pass' with no tool use" \
    || no "stop-validator did not block (exit $EXIT, expected 2)"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "[hard] CLAIM 5: 'install-guard blocks Writes to ~/.claude/settings.json'"
EXIT=$(printf '%s' "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TEST_HOME/.claude/settings.json\",\"content\":\"hi\"}}" \
    | env -u GMOS_ADMIN_OVERRIDE HOME="$TEST_HOME" GMOS_HOME="$TEST_GMOS" \
        bash "$TEST_HOME/.claude/hooks/install-guard.sh" >/dev/null 2>&1; echo $?)
[ "$EXIT" = "2" ] \
    && ok "install-guard BLOCKED a Write to ~/.claude/settings.json (exit 2)" \
          "fed a synthetic Write tool call targeting the protected path" \
    || no "install-guard did not block (exit $EXIT, expected 2)"

EXIT=$(printf '%s' "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TEST_HOME/.claude/settings.json\",\"content\":\"hi\"}}" \
    | GMOS_ADMIN_OVERRIDE=1 HOME="$TEST_HOME" GMOS_HOME="$TEST_GMOS" \
        bash "$TEST_HOME/.claude/hooks/install-guard.sh" >/dev/null 2>&1; echo $?)
[ "$EXIT" = "0" ] \
    && ok "GMOS_ADMIN_OVERRIDE=1 lets the same write through (exit 0)" \
          "re-ran the identical call with the documented escape hatch" \
    || no "GMOS_ADMIN_OVERRIDE=1 did not bypass the guard (exit $EXIT)"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "[hard] CLAIM 6: 'Router architecture sends 0 Anthropic tokens'"
ANTHROPIC_HITS=$(grep -rEn 'api\.anthropic\.com|anthropic\.com|claude\.com/api' \
    "$REPO/router" "$REPO/hooks/routing" 2>/dev/null | wc -l | tr -d ' ')
[ "$ANTHROPIC_HITS" = "0" ] \
    && ok "0 references to any Anthropic API endpoint in router code" \
          "grep'd router/ + hooks/routing/ for anthropic.com — zero matches" \
    || no "found $ANTHROPIC_HITS Anthropic API references in router code"

OLLAMA_USES=$(grep -rln 'ollama\|OLLAMA' "$REPO/router" 2>/dev/null | wc -l | tr -d ' ')
[ "$OLLAMA_USES" -gt 0 ] \
    && ok "router uses Ollama (local LLM runtime) for embeddings" \
          "$OLLAMA_USES files in router/ reference Ollama" \
    || no "router does not appear to use Ollama"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "[hard] CLAIM 7: 'Uninstall fully reverses install'"
gmos_run "$REPO/uninstall.sh" --keep-data </dev/null >/dev/null 2>&1
SETTINGS=$(cat "$TEST_HOME/.claude/settings.json" 2>/dev/null)
SYMLINKS_LEFT=$(find "$TEST_HOME/.claude/hooks" -type l 2>/dev/null | wc -l | tr -d ' ')
[ "$SETTINGS" = "{}" ] \
    && ok "settings.json reduced to '{}' after uninstall" \
          "ran ./uninstall.sh and cat the file" \
    || no "settings.json not empty: $SETTINGS"

[ "$SYMLINKS_LEFT" = "0" ] \
    && ok "0 symlinks remain in ~/.claude/hooks/ after uninstall" \
          "counted symlinks" \
    || no "$SYMLINKS_LEFT symlinks left after uninstall"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "[hard] CLAIM 8: 'Kill switch disables all hooks without uninstalling'"
gmos_run "$REPO/install.sh" discipline >/dev/null 2>&1
touch "$TEST_HOME/.claude/.god-mode-disabled"
EXIT=$(printf '%s' "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TEST_HOME/.claude/settings.json\",\"content\":\"hi\"}}" \
    | env -u GMOS_ADMIN_OVERRIDE HOME="$TEST_HOME" GMOS_HOME="$TEST_GMOS" \
        bash "$TEST_HOME/.claude/hooks/install-guard.sh" >/dev/null 2>&1; echo $?)
[ "$EXIT" = "0" ] \
    && ok "with .god-mode-disabled present, hooks DON'T fire (exit 0)" \
          "touched the kill-switch file, re-ran the same protected-path call" \
    || no "kill switch did not disable hook (exit $EXIT)"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "[hard] CLAIM 9: 'GMOS_CHECK_* env vars in README all exist in code'"
README_VARS=$(grep -oE 'GMOS_CHECK_[A-Z_]+' "$REPO/README.md" | sort -u)
for v in $README_VARS; do
    if grep -q "$v" "$REPO/hooks/discipline/stop-validator.sh"; then
        ok "$v referenced in stop-validator.sh" "grep'd the hook source"
    else
        no "$v in README but NOT in stop-validator.sh"
    fi
done

# ════════════════════════════════════════════════════════════════════
echo ""
echo "[hard] CLAIM 10: 'Demo assets exist (4 GIFs + 8 before/after PNGs)'"
GIF_COUNT=$(ls "$REPO"/docs/demos/*.gif 2>/dev/null | wc -l | tr -d ' ')
PNG_COUNT=$(ls "$REPO"/docs/demos/before-after/*.png 2>/dev/null | wc -l | tr -d ' ')
[ "$GIF_COUNT" = "4" ] && ok "4 GIFs in docs/demos/" "ls counted them" \
                          || no "expected 4 GIFs, found $GIF_COUNT"
[ "$PNG_COUNT" = "8" ] && ok "8 before/after PNGs (4 pairs)" "ls counted them" \
                          || no "expected 8 PNGs, found $PNG_COUNT"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "============================================================"
echo "  RESULT: ${PASS} verified, ${SOFT_WARN} soft warnings, ${HARD_FAIL} failed"
echo "============================================================"
echo ""
if [ "$HARD_FAIL" = "0" ]; then
    if [ "$SOFT_WARN" = "0" ]; then
        echo "  Every load-bearing README claim is TRUE on this machine."
    else
        echo "  Behavioural claims all true. Soft warnings on timing only."
    fi
    [ "$VERBOSE" = "0" ] && echo "  Run with -v / --verbose to see how each check was performed."
    exit 0
else
    echo "  ${HARD_FAIL} hard claim(s) failed. The README is overclaiming."
    exit 1
fi
