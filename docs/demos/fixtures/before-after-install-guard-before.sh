#!/bin/bash
# Install-guard tier: BEFORE state. Agent edits your config without confirmation.
C_USER='\033[1;36m'; C_AGENT='\033[1;37m'; C_DIM='\033[2m'; C_BAD='\033[1;31m'; C_RESET='\033[0m'
echo
printf "${C_DIM}# Without god-mode-os: agent can rewrite your config silently${C_RESET}\n"
echo
printf "${C_USER}> ${C_RESET}Add a new PostToolUse hook to my Claude Code config.\n"
sleep 0.1
printf "${C_AGENT}claude:${C_RESET} Writing the new hook entry to ~/.claude/settings.json.\n"
printf "${C_DIM}  [Write tool: ~/.claude/settings.json]${C_RESET}  ${C_BAD}executed${C_RESET}\n"
printf "${C_DIM}  [merged into existing JSON, malformed indentation, lost two stop hooks]${C_RESET}\n"
echo
printf "${C_BAD}# Next session: missing hooks, no warning. You find out via a bug.${C_RESET}\n"
echo
