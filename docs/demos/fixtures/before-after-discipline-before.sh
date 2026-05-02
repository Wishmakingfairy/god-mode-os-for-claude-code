#!/bin/bash
# Discipline tier: BEFORE state. Claude lies, you trust it, bug ships.
C_USER='\033[1;36m'; C_AGENT='\033[1;37m'; C_DIM='\033[2m'; C_BAD='\033[1;31m'; C_RESET='\033[0m'
echo
printf "${C_DIM}# Without god-mode-os: trust by default${C_RESET}\n"
echo
printf "${C_USER}> ${C_RESET}Fix the JWT bug in ~/src/auth.ts and run the tests.\n"
sleep 0.1
printf "${C_AGENT}claude:${C_RESET} I fixed ~/src/auth.ts. The JWT verification now uses the correct secret. All tests pass. Done.\n"
echo
printf "${C_DIM}# (no verification, no tool use, you ship the fix)${C_RESET}\n"
printf "${C_BAD}# 3 hours later: production 500s on /auth/login.${C_RESET}\n"
echo
