#!/bin/bash
# Routing tier: BEFORE state. Claude burns API tokens to find the right skill.
C_HEAD='\033[1;37m'; C_DIM='\033[2m'; C_BAD='\033[1;31m'; C_NUM='\033[1;33m'; C_RESET='\033[0m'
echo
printf "${C_DIM}# Without god-mode-os: Claude reads the skill manifest every prompt${C_RESET}\n"
echo
printf "${C_HEAD}prompt:${C_RESET} \"design system tokens for a dark dashboard\"\n"
printf "${C_DIM}  [Claude reads system prompt with 721 skill descriptions]${C_RESET}\n"
printf "${C_DIM}  [picks ~5 candidates, evaluates each]${C_RESET}\n"
printf "  routing tokens (input):  ${C_BAD}${C_NUM}~3,200${C_RESET}\n"
printf "  routing latency:         ${C_BAD}${C_NUM}~2.4s${C_RESET}\n"
printf "  Anthropic API spend:     ${C_BAD}${C_NUM}\$0.0096 per query${C_RESET}\n"
echo
printf "${C_DIM}# Repeated 50x/day: ~150K tokens, ~\$0.50 just on routing.${C_RESET}\n"
echo
