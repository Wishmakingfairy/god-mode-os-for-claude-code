#!/bin/bash
# Install-guard tier: AFTER state. Hook intercepts; you authorize explicitly.
C_USER='\033[1;36m'; C_AGENT='\033[1;37m'; C_DIM='\033[2m'; C_OK='\033[1;32m'; C_BLK='\033[1;31m'; C_RESET='\033[0m'
echo
printf "${C_DIM}# With god-mode-os install-guard: writes need explicit approval${C_RESET}\n"
echo
printf "${C_USER}> ${C_RESET}Add a new PostToolUse hook to my Claude Code config.\n"
sleep 0.1
printf "${C_AGENT}claude:${C_RESET} Writing the new hook entry to ~/.claude/settings.json.\n"
printf "  ${C_BLK}INSTALL/CONFIG GUARD BLOCK${C_RESET}: Write on protected path: ~/.claude/settings.json\n"
printf "${C_AGENT}claude:${C_RESET} Surfacing for explicit approval before retry.\n"
printf "${C_USER}> ${C_RESET}Approved. Override and retry.\n"
printf "${C_DIM}  \$ GMOS_ADMIN_OVERRIDE=1 <retry>${C_RESET}\n"
printf "${C_DIM}  [Write tool: ~/.claude/settings.json] ${C_OK}✓ written${C_RESET}\n"
printf "${C_OK}✓ approved write to ~/.claude/settings.json${C_RESET}\n"
echo
