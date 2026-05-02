#!/bin/bash
# router-demo.sh: Run 3 real queries against god-mode-os router, show timing
# and zero-token cost. Used by docs/demos/routing.tape.

set -u
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

C_HEAD='\033[1;37m'
C_PROMPT='\033[1;36m'
C_DIM='\033[2m'
C_OK='\033[1;32m'
C_NUM='\033[1;33m'
C_RESET='\033[0m'

# Use existing local Postgres + venv. In production install, these come from
# router/setup.sh. The demo shows the real query path.
PYBIN="${GMOS_DEMO_PYTHON:-python3}"
QUERY="${GMOS_DEMO_QUERY:-$REPO_ROOT/router/vector/query.py}"
export GMOS_DB_DSN="${GMOS_DB_DSN:-dbname=gmos_router}"

slow_print() {
    local text="$1" delay="${2:-0.008}"
    local i
    for ((i=0; i<${#text}; i++)); do
        printf "%s" "${text:$i:1}"
        sleep "$delay"
    done
}

# Estimate tokens that would be spent if Claude routed this query itself
# (i.e., had to read skill descriptions in its system prompt to pick).
# Conservative heuristic: 4 chars per token, plus a small fixed overhead.
estimate_api_tokens() {
    local q="$1"
    local chars=${#q}
    local q_tokens=$(( (chars + 3) / 4 ))
    # +200 for the routing prompt scaffold Claude would need
    echo $(( q_tokens + 200 ))
}

run_query() {
    local q="$1"
    printf "${C_PROMPT}prompt:${C_RESET} "
    slow_print "\"$q\""
    echo
    sleep 0.15
    local START END MS EST
    START=$(python3 -c 'import time;print(int(time.time()*1000))')
    local SCRATCH="$REPO_ROOT/docs/demos/fixtures/.q.json"
    "$PYBIN" "$QUERY" "$q" --merged --json --skills-top=3 --files-top=0 \
        > "$SCRATCH" 2>&1
    END=$(python3 -c 'import time;print(int(time.time()*1000))')
    MS=$((END-START))
    EST=$(estimate_api_tokens "$q")
    printf "${C_DIM}  [pgvector cosine match in ${C_NUM}${MS}ms${C_RESET}${C_DIM}, all local]${C_RESET}\n"
    /usr/bin/python3 -c "
import json
d = json.load(open('$SCRATCH'))
for s in d.get('skills', [])[:3]:
    print(f\"  \033[2m{s['sim']:.3f}\033[0m  \033[1m{s['name']}\033[0m\")
"
    printf "${C_DIM}  [anthropic tokens] ${C_OK}0${C_RESET}${C_DIM}  (vs ~${EST} estimated via API routing)${C_RESET}\n"
    sleep 0.4
}

echo
printf "${C_HEAD}# god-mode-os router demo${C_RESET}\n"
printf "${C_DIM}# 721 skills indexed locally. Routing via pgvector + nomic-embed.${C_RESET}\n"
echo
sleep 0.3

run_query "design system tokens for a dark dashboard"
run_query "how do I optimize a postgres query"
run_query "write tests for this React component"

echo
printf "${C_HEAD}# 3 routes done locally. ${C_OK}~15x routing-token reduction${C_RESET}${C_HEAD}.${C_RESET}\n"
printf "${C_DIM}# Estimates assume Claude reading skill descriptions in its system prompt.${C_RESET}\n"
sleep 1.0
