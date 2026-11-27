#!/bin/bash
# push-gate.sh : PreToolUse hook on Bash. Opt-in.
# Stops the agent from publishing code without a fresh, explicit yes from the user.
#
# Blocks: git push (also with -C / -c, and git subtree push), git remote add / set-url,
#         gh repo create / edit / transfer / fork, gh pr create / merge, gh release create,
#         gh gist create, gh api with a write method, hub push.
# Not covered: anything that publishes without these words (a custom script, an alias,
#         git send-pack, a CI trigger). See "Honest limit" below.
# It can over-block: the words are matched anywhere in the command, so a note that merely
#         contains them (inside quoted text) is stopped too. That is the safer direction for a gate.
#
# Switch it on:   touch ~/.god-mode-os/push-gate-on     (or set GMOS_PUSH_GATE=1)
# Switch it off:  rm ~/.god-mode-os/push-gate-on        (the install guard stops the agent doing this)
#
# A publish command goes through only when a fresh approval exists at ~/.god-mode-os/push-approved:
#   TARGET=<owner> VIS=<private|public>
# <owner> is the GitHub user or organisation. Rules:
#   - single-use, and it expires after 15 minutes (GMOS_PUSH_TOKEN_MAX_AGE, in seconds)
#   - it covers ONE publish command; a line holding two is blocked, approval or not
#   - VIS=private does not cover --public or a switch to public
#   - the owner is read from the URL or remote the command names, not just from origin
#
# Honest limit: the agent has a shell, so it could write the approval file itself. This gate
# is a speed bump that forces the question to be asked, not a lock.
#
# Honors the kill switch and GMOS_ADMIN_OVERRIDE=1. Exit 0 = allow. Exit 2 + stderr = block.
# Once a publish command has been recognised, any internal error blocks (fail closed).

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

GMOS_HOME="${GMOS_HOME:-$HOME/.god-mode-os}"
KILL_SWITCH="${GMOS_KILL_SWITCH:-$HOME/.claude/.god-mode-disabled}"

[ -f "$KILL_SWITCH" ] && exit 0
[ "${GMOS_ADMIN_OVERRIDE:-}" = "1" ] && exit 0
if [ "${GMOS_PUSH_GATE:-0}" != "1" ] && [ ! -f "$GMOS_HOME/push-gate-on" ]; then
    exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
    >&2 echo "push-gate: python3 not found, this command was NOT checked (warning only)"
    exit 0
fi

IFS= read -r -d '' GATE_PY <<'PY'
import json, os, re, subprocess, sys, time

GMOS_HOME = os.environ["GATE_HOME"]
TOKEN_FILE = os.environ.get("GMOS_PUSH_TOKEN") or os.path.join(GMOS_HOME, "push-approved")
try:
    MAX_AGE = int(os.environ.get("GMOS_PUSH_TOKEN_MAX_AGE") or 900)
except ValueError:
    MAX_AGE = 900

try:
    data = json.load(sys.stdin)
    cmd = (data.get("tool_input") or {}).get("command") or ""
    cwd = data.get("cwd") or os.getcwd()
except Exception:
    sys.exit(0)
if not cmd:
    sys.exit(0)

ARG = r"""(?:"[^"]*"|'[^']*'|\S+)"""
GIT = r"\bgit(?:\s+(?:-[Cc]\s+" + ARG + r"|--?[A-Za-z][^\s]*))*\s+"
GH = r"(?:^|[\s;|&(`])gh\s+"
ACTIONS = [
    ("git push", GIT + r"(?:subtree\s+)?push\b"),
    ("git remote change", GIT + r"remote\s+(?:add|set-url)\b"),
    ("gh repo create", GH + r"repo\s+create\b"),
    ("gh repo edit", GH + r"repo\s+edit\b"),
    ("gh repo transfer", GH + r"repo\s+transfer\b"),
    ("gh repo fork", GH + r"repo\s+fork\b"),
    ("gh pr create", GH + r"pr\s+create\b"),
    ("gh pr merge", GH + r"pr\s+merge\b"),
    ("gh release create", GH + r"release\s+create\b"),
    ("gh gist create", GH + r"gist\s+create\b"),
    ("gh api write", GH + r"api\b[^\n;|&]*(?:(?:-X|--method)[\s=]*(?:POST|PUT|PATCH|DELETE)\b|\s-[fF]\s|\s--(?:raw-)?field\b|\s--input\b)"),
    ("hub push", r"\bhub\s+push\b"),
]
found = []
for kind, pattern in ACTIONS:
    for m in re.finditer(pattern, cmd, re.I if kind == "gh api write" else 0):
        found.append((m.start(), kind, m))
if not found:
    sys.exit(0)
# gh api: an explicit GET wins, and a graphql call is a write only when it is a mutation
def api_is_read(m):
    seg = re.split(r"[;&|\n]", cmd[m.start():], maxsplit=1)[0]
    if re.search(r"(?:-X|--method)[\s=]*GET\b", seg, re.I):
        return True
    if re.search(r"\bapi\s+graphql\b", seg) and not re.search(r"(?:-X|--method)[\s=]*(?:POST|PUT|PATCH|DELETE)\b", seg, re.I):
        return "mutation" not in seg
    return False


found = [f for f in found if not (f[1] == "gh api write" and api_is_read(f[2]))]
if not found:
    sys.exit(0)
found.sort(key=lambda x: x[0])


def block(msg):
    sys.stderr.write(msg.rstrip() + "\n")
    sys.exit(2)


try:
    kind = found[0][1]
    if len(found) > 1:
        block("PUSH GATE BLOCKED: this command line holds %d publish commands (%s). One approval covers one "
              "publish command. Run them one at a time, each with its own approval from the user."
              % (len(found), ", ".join(k for _, k, _ in found)))

    owners = []
    for o in re.findall(r"github\.com[:/]([A-Za-z0-9_.-]+)", cmd):
        if o.lower() not in [x.lower() for x in owners]:
            owners.append(o)
    if len(owners) > 1:
        block("PUSH GATE BLOCKED: the command names more than one GitHub owner (%s). Publish to one at a time."
              % ", ".join(owners))

    owner = owners[0] if owners else ""
    if not owner:
        m = re.search(r"repo\s+(?:create|edit|transfer|fork)\s+([A-Za-z0-9_.-]+)/", cmd)
        if m:
            owner = m.group(1)
    if not owner and kind in ("git push", "git remote change", "hub push", "gh pr create"):
        # which folder, and which remote, does the command name?
        where = cwd
        m = re.search(r"\bgit(?:\s+-c\s+\S+|\s+--?[A-Za-z][^\s]*)*\s+-C\s+(" + ARG + ")", cmd)
        if m:
            d = m.group(1).strip("'\"")
            d = os.path.expanduser(d)
            where = d if os.path.isabs(d) else os.path.join(cwd, d)
        remote = "origin"
        if kind == "git push":
            tail = cmd[found[0][2].end():]
            tail = re.split(r"[;&|\n]", tail, maxsplit=1)[0]
            words = [w for w in tail.split() if not w.startswith("-")]
            if words:
                remote = words[0].strip("'\"")
        url = ""
        for name in (remote, "origin"):
            try:
                url = subprocess.run(["git", "-C", where, "remote", "get-url", name], capture_output=True,
                                     text=True, timeout=5).stdout.strip()
            except Exception:
                url = ""
            if url:
                break
            if name == remote and remote != "origin":
                # a remote was named and it cannot be resolved: do not fall back to origin
                url = ""
                break
        m = re.search(r"github\.com[:/]([A-Za-z0-9_.-]+)", url)
        if m:
            owner = m.group(1)
    if not owner:
        owner = "UNKNOWN"

    wants_public = bool(re.search(r"--public\b|--visibility[\s=]+public\b|visibility=public\b", cmd))

    if os.path.isfile(TOKEN_FILE):
        age = time.time() - os.path.getmtime(TOKEN_FILE)
        text = open(TOKEN_FILE).read()
        mt = re.search(r"TARGET=([A-Za-z0-9_.-]+)", text)
        mv = re.search(r"VIS=([a-z]+)", text)
        tok_target = mt.group(1) if mt else ""
        tok_vis = mv.group(1) if mv else ""
        if age > MAX_AGE or age < -60:
            os.remove(TOKEN_FILE)
            block("PUSH GATE: the approval has expired. Ask the user again.")
        if owner == "UNKNOWN" or tok_target.upper() == "UNKNOWN":
            os.remove(TOKEN_FILE)
            block("PUSH GATE: the gate cannot tell which GitHub owner this command publishes to, so no approval "
                  "can cover it. Name the destination in the command (a full https://github.com/<owner>/<repo> "
                  "address, or <owner>/<repo>), then ask the user again.")
        if not tok_target or tok_target.lower() != owner.lower():
            block("PUSH GATE: the approval was for '%s', this command targets '%s'. Ask the user again."
                  % (tok_target, owner))
        if wants_public and tok_vis != "public":
            block("PUSH GATE: the approval was for a %s repo, this command makes something public. "
                  "Ask the user again and record VIS=public only if they say so." % (tok_vis or "private"))
        os.remove(TOKEN_FILE)
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext":
              "Push gate: approved for %s (%s). Approval used up. Any further publish command needs a new one."
              % (owner, tok_vis or "visibility not stated")}}))
        sys.exit(0)

    block("""PUSH GATE BLOCKED: %s -> %s

Nothing gets published without the user's explicit go-ahead. Before retrying, ask them and
get an answer to BOTH:

  1. Destination: which GitHub user or organisation?
  2. Visibility:  private or public? The default is private. Never assume public.

Also say plainly what is being pushed: which repo, which branch, which files.

When they have answered, record the approval and retry:

  mkdir -p "%s"
  echo "TARGET=<owner> VIS=<private|public>" > "%s"

The approval is single-use, covers one publish command, and expires after %d minutes."""
          % (kind, owner, GMOS_HOME, TOKEN_FILE, MAX_AGE // 60))
except SystemExit:
    raise
except Exception as e:
    block("PUSH GATE BLOCKED: a publish command was recognised but the gate hit an internal error (%s). "
          "Blocking to be safe. The user can run the command themselves." % type(e).__name__)
PY

GATE_HOME="$GMOS_HOME" python3 -I -c "$GATE_PY"
RC=$?
# 0 = allow, 2 = block. Anything else means the checker itself broke: say so, do not block all Bash.
if [ "$RC" -ne 0 ] && [ "$RC" -ne 2 ]; then
    >&2 echo "push-gate: the checker could not run (exit $RC), this command was NOT checked (warning only)"
    exit 0
fi
exit "$RC"
