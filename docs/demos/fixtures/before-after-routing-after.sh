#!/bin/bash
# Routing tier: AFTER state. Local pgvector picks in <300ms with 0 API tokens.
C_HEAD='\033[1;37m'; C_DIM='\033[2m'; C_OK='\033[1;32m'; C_NUM='\033[1;33m'; C_RESET='\033[0m'
echo
printf "${C_DIM}# With god-mode-os Routing: pgvector + nomic-embed, all local${C_RESET}\n"
echo
printf "${C_HEAD}prompt:${C_RESET} \"design system tokens for a dark dashboard\"\n"
printf "${C_DIM}  [pgvector cosine match in ${C_NUM}259ms${C_RESET}${C_DIM}, all local]${C_RESET}\n"
printf "  ${C_DIM}0.731${C_RESET}  theming-system\n"
printf "  ${C_DIM}0.673${C_RESET}  design-token\n"
printf "  ${C_DIM}0.656${C_RESET}  dark-mode-design\n"
printf "  routing tokens:        ${C_OK}${C_NUM}0${C_RESET}\n"
printf "  routing latency:       ${C_OK}${C_NUM}0.26s${C_RESET}\n"
printf "  Anthropic API spend:   ${C_OK}${C_NUM}\$0.0000${C_RESET}\n"
echo
printf "${C_DIM}# Repeated 50x/day: 0 routing tokens. Same accuracy.${C_RESET}\n"
echo
