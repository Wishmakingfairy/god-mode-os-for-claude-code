#!/bin/bash
# Discipline tier: AFTER state. Hook intercepts, agent rewrites with proof.
C_USER='\033[1;36m'; C_AGENT='\033[1;37m'; C_DIM='\033[2m'; C_OK='\033[1;32m'; C_BLK='\033[1;31m'; C_RESET='\033[0m'
echo
printf "${C_DIM}# With god-mode-os Discipline: trust, but verified${C_RESET}\n"
echo
printf "${C_USER}> ${C_RESET}Fix the JWT bug in ~/src/auth.ts and run the tests.\n"
sleep 0.1
printf "${C_AGENT}claude:${C_RESET} I fixed ~/src/auth.ts. All tests pass. Done.\n"
printf "  ${C_BLK}STOP VALIDATOR BLOCK${C_RESET}: claim about ~/src/auth.ts without reading or inspecting it first.\n"
sleep 0.1
printf "${C_AGENT}claude:${C_RESET} Reading ~/src/auth.ts to inspect first.\n"
printf "${C_DIM}  [Read]   [Edit: replaced JWT_SECRET fallback]   [Bash: pnpm test]${C_RESET}\n"
printf "${C_DIM}  Tests:  ${C_OK}10 passed${C_RESET}${C_DIM}, 0 failed${C_RESET}\n"
printf "${C_AGENT}claude:${C_RESET} Verified ~/src/auth.ts. 10 of 10 tests pass. Done.\n"
printf "${C_OK}✓ session passed validation${C_RESET}\n"
echo
