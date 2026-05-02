#!/bin/bash
# simulated-session.sh: replay a stub Claude session for demo recording.
# Prints user + assistant turns with realistic delays, then auto-invokes the
# real stop-validator hook (no manual pipe). Used by docs/demos/discipline.tape.

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/docs/demos/fixtures"

C_USER='\033[1;36m'   # cyan bold
C_AGENT='\033[1;37m'  # white bold
C_DIM='\033[2m'
C_OK='\033[1;32m'
C_RESET='\033[0m'

slow_print() {
    local text="$1" delay="${2:-0.018}"
    local i
    for ((i=0; i<${#text}; i++)); do
        printf "%s" "${text:$i:1}"
        sleep "$delay"
    done
}

echo
printf "${C_DIM}# simulated Claude Code session, hooks active${C_RESET}\n"
sleep 0.5

printf "${C_USER}> ${C_RESET}"
slow_print "Fix the JWT bug in ~/src/auth.ts and run the tests."
echo
sleep 0.6

printf "${C_AGENT}claude:${C_RESET} "
slow_print "I fixed ~/src/auth.ts. The JWT verification now uses the correct secret. All tests pass. Done." 0.012
echo
sleep 0.4

# Real hook fires automatically on Stop event. Invoke it on the fixture transcript.
sleep 0.3
cat "$FIXTURE_DIR/stop-input.json" | \
    GMOS_HOME=/tmp/gmos-demo \
    GMOS_KILL_SWITCH=/nonexistent \
    GMOS_CHECK_EM_DASH=0 \
    GMOS_CHECK_CONSISTENCY=0 \
    GMOS_CHECK_DODGE=0 \
    GMOS_CHECK_CITATIONS=0 \
    bash "$REPO_ROOT/hooks/discipline/stop-validator.sh" 2>&1 | sed "s/^/  /"

sleep 1.2

printf "${C_DIM}# Claude is forced to rewrite. Watch what changes:${C_RESET}\n"
sleep 0.6

printf "${C_AGENT}claude:${C_RESET} "
slow_print "Reading ~/src/auth.ts to inspect first." 0.012
echo
sleep 0.3
printf "${C_DIM}  [Read tool: ~/src/auth.ts, 84 lines]${C_RESET}\n"
sleep 0.5
printf "${C_DIM}  [Edit tool: replaced JWT_SECRET fallback]${C_RESET}\n"
sleep 0.5
printf "${C_DIM}  [Bash tool: pnpm test --filter auth]${C_RESET}\n"
sleep 0.4
printf "${C_DIM}  Tests:  ${C_OK}10 passed${C_RESET}${C_DIM}, 0 failed${C_RESET}\n"
sleep 0.6

printf "${C_AGENT}claude:${C_RESET} "
slow_print 'Verified ~/src/auth.ts. 10 of 10 tests pass. Done.' 0.012
echo
sleep 0.6
printf "${C_OK}✓ session passed validation${C_RESET}\n"
sleep 0.8
