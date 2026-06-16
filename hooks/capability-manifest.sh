#!/bin/bash
# capability-manifest.sh : SessionStart hook.
# Injects a LIVE, accurate capability inventory so the assistant never falsely claims it
# lacks a skill / MCP / tool that is actually available. Local-only, no network calls.
# Fast and fail-safe: on any error it emits a minimal manifest and exits 0.

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

python3 - <<'PYEOF' 2>/dev/null || echo '{"additionalContext":"Capability note: you have a skill-router (search_skills/get_skill) plus MCP servers. Never claim you lack a skill/tool/browser without first calling search_skills or checking /mcp."}'
import json, glob, pathlib
HOME = pathlib.Path.home()

# MCP servers (from .mcp.json), the real configured set
mcps = []
try:
    d = json.load(open(HOME/".claude"/".mcp.json"))
    mcps = list((d.get("mcpServers") or {}).keys())
except Exception:
    pass

# Skill counts (active pool + library), best-effort
_JUNK = ("node_modules", ".venv", "site-packages", "skills-archive", "__pycache__")
def count_skills(root):
    try:
        return sum(1 for p in glob.iglob(str(root/"**"/"SKILL.md"), recursive=True)
                   if not any(j in p for j in _JUNK))
    except Exception:
        return 0
active = count_skills(HOME/".claude"/"skills")
library = count_skills(HOME/".claude"/"skills-library")

# Plugins
plugins = []
try:
    pdir = HOME/".claude"/"plugins"
    if pdir.exists():
        plugins = [p.name for p in pdir.iterdir() if p.is_dir() and not p.name.startswith(".")][:20]
except Exception:
    pass

router = "skill-router" in mcps
parts = []
parts.append(f"LIVE CAPABILITY MANIFEST (session start). Skills reachable: ~{active+library} "
             f"(active {active} + library {library}).")
if router:
    parts.append("Skill access: call search_skills(query) to find relevant skills from the full bank, "
                 "then get_skill(name) to load one. Do not rely on the in-context skill list alone.")
parts.append("MCP servers configured: " + (", ".join(mcps) if mcps else "(none found)") + ".")
if plugins:
    parts.append("Plugins: " + ", ".join(plugins) + ".")
parts.append("RULE: before claiming you cannot do something (browse, search, use a tool/skill/MCP), "
             "first call search_skills or check /mcp. MCP tools may be DEFERRED (loaded on search), so "
             "absence from the in-context list does NOT mean the capability is missing. Distinguish "
             "'not connected' (fix it) from 'connected but not yet loaded' (search/load it).")
print(json.dumps({"additionalContext": " ".join(parts)}))
PYEOF
