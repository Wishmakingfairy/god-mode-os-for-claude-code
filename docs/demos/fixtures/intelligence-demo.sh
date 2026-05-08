#!/bin/bash
# intelligence-demo.sh: Daily digest pipeline. Plumbing compressed, digest
# preview gets the screen time. Used by docs/demos/intelligence.tape.

set -u
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

C_HEAD='\033[1;37m'
C_DIM='\033[2m'
C_OK='\033[1;32m'
C_MUST='\033[1;36m'
C_SKIP='\033[38;5;240m'   # darker gray for "focus-protection" framing
C_RESET='\033[0m'

DEMO_HOME="$HOME/.god-mode-os/scratch/intel-demo"
mkdir -p "$DEMO_HOME/intelligence"
DATE=$(date +%Y-%m-%d)
DIGEST="$DEMO_HOME/intelligence/$DATE.md"
INBOX="$DEMO_HOME/intelligence/INBOX.md"
CACHED="$REPO_ROOT/docs/demos/fixtures/digest-body.md"

echo
printf "${C_DIM}# launchd 07:00, com.god-mode-os.intelligence-monitor${C_RESET}\n"
sleep 0.3

# === Plumbing (compressed) ===
printf "${C_DIM}==> ${C_OK}✓${C_RESET}${C_DIM} 5 feeds in 1.2s, LLM synthesis, digest written${C_RESET}\n"
sleep 0.6

# Build the digest from cached LLM output and split into Must Know / Skip
DIGEST_BODY=$(cat "$CACHED" 2>/dev/null || echo "Must Know: example. Skip: example.")
cat > "$DIGEST" <<DIGEST_EOF
# Intelligence Digest $DATE

$DIGEST_BODY
DIGEST_EOF
{
    echo "## Intelligence digest $DATE"
    echo "- [Open digest]($DIGEST)"
    echo ""
} >> "$INBOX"

# === Artifact: gets the screen time ===
echo
printf "${C_HEAD}~/.god-mode-os/intelligence/${DATE}.md${C_RESET}\n"
echo
sleep 0.4

# Print the digest with explicit per-line styling so Skip is dimmed
printf "  ${C_HEAD}# Intelligence Digest $DATE${C_RESET}\n"
echo
sleep 0.3
while IFS= read -r line; do
    if [[ "$line" =~ ^Must\ Know: ]]; then
        printf "  ${C_MUST}must read${C_RESET}  ${line}\n"
    elif [[ "$line" =~ ^Skip: ]]; then
        printf "  ${C_SKIP}focus-protect${C_RESET}  ${C_SKIP}${line}${C_RESET}\n"
    elif [[ -n "$line" ]]; then
        printf "  ${line}\n"
    fi
    sleep 0.4
done < "$CACHED"

sleep 1.0
echo
printf "${C_DIM}# desktop notification fired (macOS terminal-notifier; Linux: notify-send)${C_RESET}\n"
sleep 0.4
printf "${C_DIM}# INBOX.md gets one line per digest. Bookmark and check daily.${C_RESET}\n"
sleep 1.0
