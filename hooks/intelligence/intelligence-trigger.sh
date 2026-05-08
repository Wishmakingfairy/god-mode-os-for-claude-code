#!/bin/bash
# intelligence-trigger.sh — SessionStart hook for Tier 3.
#
# Fires off the Claude Code SessionStart event (not a clock cron).
# Lazy-runs the intelligence-monitor + three-day-overview only when their
# output is stale, in the background, so it never blocks session start.
#
# Why this design:
# - Tied to user's actual activity. If you skip a day of Claude Code,
#   you don't get a stale digest you'll never read.
# - Idempotent: once today's digest exists, this hook is a no-op for
#   the rest of the day's sessions.
# - Async: spawns the generators in background, returns to Claude
#   immediately. Zero added session-start latency.
# - Honors kill switch.

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
set -u

GMOS_HOME="${GMOS_HOME:-$HOME/.god-mode-os}"
KILL_SWITCH="${GMOS_KILL_SWITCH:-$HOME/.claude/.god-mode-disabled}"

# Resolve the repo this hook was symlinked from so we can find its siblings.
SELF_REAL=$(readlink "$0" 2>/dev/null || echo "$0")
HOOK_DIR=$(cd "$(dirname "$SELF_REAL")" && pwd)
INTEL_DIR="$GMOS_HOME/intelligence"
REPORTS_DIR="$GMOS_HOME/reports"

# Bail fast if disabled.
[ -f "$KILL_SWITCH" ] && exit 0

mkdir -p "$INTEL_DIR" "$REPORTS_DIR" 2>/dev/null

# ─── daily digest: trigger if today's file does not yet exist ──────
TODAY=$(date +%Y-%m-%d)
TODAY_FILE="$INTEL_DIR/$TODAY.md"
if [ ! -f "$TODAY_FILE" ] && [ -x "$HOOK_DIR/intelligence-monitor.sh" ]; then
    nohup bash "$HOOK_DIR/intelligence-monitor.sh" \
        >> "$GMOS_HOME/intelligence-monitor.stdout.log" \
        2>> "$GMOS_HOME/intelligence-monitor.stderr.log" </dev/null &
    disown 2>/dev/null || true
fi

# ─── 3-day overview: trigger if last overview is from 3+ calendar
# days ago, or there is no overview yet. ──────────────────────────
LATEST_OVERVIEW=$(ls -1t "$REPORTS_DIR"/3day-overview-*.md 2>/dev/null | head -1)
SHOULD_RUN_OVERVIEW=0
if [ -z "$LATEST_OVERVIEW" ]; then
    SHOULD_RUN_OVERVIEW=1
else
    # Extract YYYY-MM-DD from filename, compare to 3 days ago in seconds.
    LAST_DATE=$(basename "$LATEST_OVERVIEW" .md | sed -E 's/^3day-overview-//')
    if [ -n "$LAST_DATE" ]; then
        # `date -j` on macOS, `date -d` on Linux. Try both.
        LAST_TS=$(date -j -f "%Y-%m-%d" "$LAST_DATE" "+%s" 2>/dev/null \
              || date -d "$LAST_DATE" "+%s" 2>/dev/null \
              || echo 0)
        NOW_TS=$(date +%s)
        AGE_DAYS=$(( (NOW_TS - LAST_TS) / 86400 ))
        [ "$AGE_DAYS" -ge 3 ] && SHOULD_RUN_OVERVIEW=1
    fi
fi
if [ "$SHOULD_RUN_OVERVIEW" = "1" ] && [ -x "$HOOK_DIR/three-day-overview.sh" ]; then
    nohup bash "$HOOK_DIR/three-day-overview.sh" \
        >> "$GMOS_HOME/three-day-overview.stdout.log" \
        2>> "$GMOS_HOME/three-day-overview.stderr.log" </dev/null &
    disown 2>/dev/null || true
fi

exit 0
