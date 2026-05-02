#!/bin/bash
# Intelligence tier: AFTER state. One file at 7am with Must Know + focus-protect Skip.
C_HEAD='\033[1;37m'; C_DIM='\033[2m'; C_MUST='\033[1;36m'; C_SKIP='\033[38;5;240m'; C_OK='\033[1;32m'; C_RESET='\033[0m'
DATE=$(date +%Y-%m-%d)
echo
printf "${C_DIM}# With god-mode-os Intelligence: one file, 7am, signal-only${C_RESET}\n"
echo
printf "${C_HEAD}~/.god-mode-os/intelligence/${DATE}.md${C_RESET}\n"
echo
printf "  ${C_HEAD}# Intelligence Digest ${DATE}${C_RESET}\n"
printf "  ${C_MUST}must read${C_RESET}      Must Know: Anthropic released the Skills v2 specification.\n"
printf "  ${C_SKIP}focus-protect  Skip: HN discussions on hook maintenance instability.${C_RESET}\n"
echo
printf "${C_OK}# 90 seconds to read. INBOX.md keeps the index. Done.${C_RESET}\n"
echo
