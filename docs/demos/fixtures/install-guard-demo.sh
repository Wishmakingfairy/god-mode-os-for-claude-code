#!/bin/bash
# install-guard-demo.sh: Show install-guard blocking a Write to ~/.claude/,
# then the agent pivoting and the user authorizing an override that succeeds.
# Used by docs/demos/install-guard.tape.

set -u
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

C_USER='\033[1;36m'
C_AGENT='\033[1;37m'
C_DIM='\033[2m'
C_OK='\033[1;32m'
C_WARN='\033[1;33m'
C_RESET='\033[0m'

slow_print() {
    local text="$1" delay="${2:-0.012}"
    local i
    for ((i=0; i<${#text}; i++)); do
        printf "%s" "${text:$i:1}"
        sleep "$delay"
    done
}

mask() {
    sed "s|$HOME|~|g"
}

echo
printf "${C_DIM}# simulated Claude Code session, hooks active${C_RESET}\n"
sleep 0.3

printf "${C_USER}> ${C_RESET}"
slow_print "Add a new PostToolUse hook to my Claude Code config."
echo
sleep 0.4

printf "${C_AGENT}claude:${C_RESET} "
slow_print "Writing the new hook entry to ~/.claude/settings.json."
echo
sleep 0.3
printf "${C_DIM}  [Write tool: ~/.claude/settings.json]${C_RESET}\n"
sleep 0.3

# Block: real install-guard fires on the fixture write.
cat "$REPO_ROOT/docs/demos/fixtures/pretooluse-write.json" | \
    GMOS_HOME="$HOME/.god-mode-os/scratch" \
    GMOS_KILL_SWITCH=/nonexistent \
    bash "$REPO_ROOT/hooks/discipline/install-guard.sh" 2>&1 | \
    mask | \
    head -1 | \
    sed "s/^/  /"

sleep 0.6

# Agent pivots, doesn't loop or hallucinate.
printf "${C_AGENT}claude:${C_RESET} "
slow_print "Blocked at PreToolUse. Surfacing for explicit approval before retry."
echo
sleep 0.6

# User authorizes
printf "${C_USER}> ${C_RESET}"
slow_print "Approved. Override and retry."
echo
sleep 0.4

printf "${C_DIM}  \$ GMOS_ADMIN_OVERRIDE=1 <retry>${C_RESET}\n"
sleep 0.3

# Real run with override succeeds (exit 0). Verify it really exits 0.
cat "$REPO_ROOT/docs/demos/fixtures/pretooluse-write.json" | \
    GMOS_HOME="$HOME/.god-mode-os/scratch" \
    GMOS_KILL_SWITCH=/nonexistent \
    GMOS_ADMIN_OVERRIDE=1 \
    bash "$REPO_ROOT/hooks/discipline/install-guard.sh" >/dev/null 2>&1
RC=$?
if [ "$RC" -eq 0 ]; then
    printf "${C_DIM}  [Write tool: ~/.claude/settings.json] ${C_OK}✓ written${C_RESET}\n"
fi

sleep 0.8
printf "${C_OK}✓ approved write to ~/.claude/settings.json${C_RESET}\n"
sleep 0.3
printf "${C_DIM}# Surgical, not punitive. Agent stops on the wrong path, retries on the right one.${C_RESET}\n"
sleep 1.0
