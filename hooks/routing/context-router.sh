#!/bin/bash
# context-router.sh — UserPromptSubmit hook
# Routes user prompt to relevant skills via local pgvector lookup.
# Zero Anthropic tokens spent on routing itself.
#
# Two outputs:
#   1. Top matched skill names injected as additionalContext to Claude.
#   2. Optional: relevant file snippets from indexed personal docs.
#
# Honors kill switch. Silent exit if no matches found (0 tokens injected).
#
# Configuration (env vars):
#   GMOS_ROUTER_PYTHON     Python venv binary. Default: /usr/bin/python3
#   GMOS_ROUTER_QUERY      Path to query.py. Default: discovered.
#   GMOS_ROUTER_TOP_SKILLS Number of skills to inject. Default: 3
#   GMOS_ROUTER_THRESHOLD  Cosine threshold for short prompts. Default: 0.55

set -u

GMOS_HOME="${GMOS_HOME:-$HOME/.god-mode-os}"
KILL_SWITCH="${GMOS_KILL_SWITCH:-$HOME/.claude/.god-mode-disabled}"
ROUTER_PY="${GMOS_ROUTER_PYTHON:-/usr/bin/python3}"
ROUTER_QUERY="${GMOS_ROUTER_QUERY:-$GMOS_HOME/router/query.py}"
TOP_SKILLS="${GMOS_ROUTER_TOP_SKILLS:-3}"
THRESHOLD="${GMOS_ROUTER_THRESHOLD:-0.55}"

[ -f "$KILL_SWITCH" ] && exit 0
[ ! -f "$ROUTER_QUERY" ] && exit 0

INPUT_FILE=$(mktemp) || exit 0
cat > "$INPUT_FILE"

"$ROUTER_PY" - "$INPUT_FILE" << PYEOF
import sys, json, os, subprocess

input_file = sys.argv[1]
try:
    with open(input_file) as f:
        data = json.load(f)
except Exception:
    sys.exit(0)
finally:
    try: os.unlink(input_file)
    except Exception: pass

prompt = data.get("prompt", "")
if not prompt or len(prompt.split()) < 3:
    sys.exit(0)

router_query = "$ROUTER_QUERY"
top = int("$TOP_SKILLS")
threshold = float("$THRESHOLD")

cmd = [sys.executable, router_query, prompt[:800], "--merged",
       f"--skills-top={top}", "--files-top=2",
       f"--skills-threshold={threshold}", "--files-threshold=0.5",
       "--json"]

try:
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=8)
    d = json.loads(r.stdout or "{}") if r.stdout else {}
except Exception:
    sys.exit(0)

skills = d.get("skills", []) or []
files = d.get("files", []) or []

parts = []
if skills:
    skill_lines = [f"- {s['name']} ({s['sim']:.2f}): {s['description'][:120]}"
                   for s in skills[:top]]
    parts.append("Relevant skills (matched via local pgvector, 0 tokens spent):\n" + "\n".join(skill_lines))

if files:
    file_lines = [f"- {os.path.basename(f.get('ref',''))}: {f.get('snippet','')[:200]}"
                  for f in files[:2]]
    parts.append("Relevant personal docs (semantic match):\n" + "\n".join(file_lines))

if parts:
    print(json.dumps({"additionalContext": "\n\n".join(parts)}))
sys.exit(0)
PYEOF

exit 0
