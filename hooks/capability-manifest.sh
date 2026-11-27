#!/bin/bash
# capability-manifest.sh : SessionStart hook.
# Adds a short, live inventory of what is installed (skills, MCP servers, plugins) to the start
# of the session, so the assistant does not claim it lacks a tool that is actually there.
# Local only, no network calls. Fail-safe: on any error it prints a one-line note and exits 0.

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

KILL_SWITCH="${GMOS_KILL_SWITCH:-$HOME/.claude/.god-mode-disabled}"
[ -f "$KILL_SWITCH" ] && exit 0

FALLBACK='{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Capability note: before claiming you cannot do something, check the installed skills and run /mcp to see connected servers."}}'

python3 - <<'PYEOF' 2>/dev/null || echo "$FALLBACK"
import json, glob, pathlib
HOME = pathlib.Path.home()

# MCP servers the user has configured (names only)
mcps = []
for cfg in (HOME / ".claude.json", HOME / ".claude" / ".mcp.json"):
    try:
        d = json.load(open(cfg))
        for name in (d.get("mcpServers") or {}).keys():
            if name not in mcps:
                mcps.append(name)
    except Exception:
        pass

# Skill count, best effort
_JUNK = ("node_modules", ".venv", "site-packages", "__pycache__")
def count_skills(root):
    try:
        return sum(1 for p in glob.iglob(str(root / "**" / "SKILL.md"), recursive=True)
                   if not any(j in p for j in _JUNK))
    except Exception:
        return 0
skills = count_skills(HOME / ".claude" / "skills")

# Plugins (folder names only)
plugins = []
try:
    pdir = HOME / ".claude" / "plugins"
    if pdir.exists():
        skip = {"cache", "marketplaces", "data", "repos"}
        plugins = sorted(p.name for p in pdir.iterdir()
                         if p.is_dir() and not p.name.startswith(".") and p.name not in skip)[:20]
except Exception:
    pass

parts = ["Installed capabilities at session start. Skills in ~/.claude/skills: %d." % skills]
parts.append("MCP servers configured: " + (", ".join(mcps[:30]) if mcps else "none found") + ".")
if plugins:
    parts.append("Plugin folders: " + ", ".join(plugins) + ".")
parts.append("Before claiming you cannot do something (browse, search, use a tool, skill or server), "
             "check the skill list and /mcp first. A tool that is not loaded yet is not the same as "
             "a tool that is missing: say which of the two it is.")
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart",
                                         "additionalContext": " ".join(parts)}}))
PYEOF
