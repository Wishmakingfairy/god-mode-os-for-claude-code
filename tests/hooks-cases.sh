#!/bin/bash
# hooks-cases.sh
# Cases for the smaller hooks: session-retro, push-gate, dash-guard.
# Usage: bash tests/hooks-cases.sh
# Everything runs in a throwaway home folder. Exit 0 on pass, 1 on fail.

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

T="$(mktemp -d 2>/dev/null || mktemp -d -t gmos-cases)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
mkdir -p "$HOME/.claude"
for v in $(env | grep -oE '^GMOS_[A-Z_]+'); do unset "$v"; done

FAILED=0
TOTAL=0
check() { # check <id> <expected exit code> <actual exit code> <what>
    TOTAL=$((TOTAL + 1))
    if [ "$2" = "$3" ]; then
        echo "OK    $1  $4"
    else
        echo "FAIL  $1  expected exit $2 got $3  $4"
        FAILED=$((FAILED + 1))
    fi
}
truth() { # truth <id> <0 if true> <what>
    TOTAL=$((TOTAL + 1))
    if [ "$2" = "0" ]; then echo "OK    $1  $3"; else echo "FAIL  $1  $3"; FAILED=$((FAILED + 1)); fi
}

# ---------- session-retro ----------
RETRO="$REPO/hooks/discipline/session-retro.sh"
TRANSCRIPT="$T/t.jsonl"
{
    echo '{"message":{"role":"user","content":"fix the build"}}'
    for i in 1 2 3 4 5 6; do
        echo '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"make build"}}]}}'
    done
} > "$TRANSCRIPT"

mkdir -p "$T/gitproj/sub" && git -C "$T/gitproj" init -q
echo "{\"transcript_path\":\"$TRANSCRIPT\",\"cwd\":\"$T/gitproj\"}" | bash "$RETRO" >/dev/null 2>&1
[ ! -d "$T/gitproj/docs/retros" ]; truth r01 $? "no retro is written inside a git repo (it could be committed by accident)"
ls "$HOME/.god-mode-os/retros/"*/*.md >/dev/null 2>&1; truth r02 $? "the retro for a git repo goes to ~/.god-mode-os/retros instead"

rm -rf "$HOME/.god-mode-os/retros"
echo "{\"transcript_path\":\"$TRANSCRIPT\",\"cwd\":\"$T/gitproj/sub\"}" | bash "$RETRO" >/dev/null 2>&1
[ ! -d "$T/gitproj/sub/docs/retros" ] && ls "$HOME/.god-mode-os/retros/"*/*.md >/dev/null 2>&1
truth r03 $? "same for a subfolder of a git repo"

rm -rf "$HOME/.god-mode-os/retros"
mkdir -p "$T/plainproj" && touch "$T/plainproj/package.json"
echo "{\"transcript_path\":\"$TRANSCRIPT\",\"cwd\":\"$T/plainproj\"}" | bash "$RETRO" >/dev/null 2>&1
[ ! -d "$T/plainproj/docs/retros" ] && ls "$HOME/.god-mode-os/retros/"*/*.md >/dev/null 2>&1
truth r04 $? "a project folder without git gets no retro either by default (it may become a repo later)"
echo "{\"transcript_path\":\"$TRANSCRIPT\",\"cwd\":\"$T/plainproj\"}" | GMOS_RETRO_IN_PROJECT=1 bash "$RETRO" >/dev/null 2>&1
ls "$T/plainproj/docs/retros/"*.md >/dev/null 2>&1; truth r05 $? "GMOS_RETRO_IN_PROJECT=1 writes the retro into docs/retros of a non-git project"

# ---------- install-guard: fallbacks and config ----------
GUARD="$REPO/hooks/discipline/install-guard.sh"
gw() { echo "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$1\"}}"; }
gw "$HOME/.claude/settings.json" | GMOS_JQ=/nonexistent/jq bash "$GUARD" >/dev/null 2>&1
check g01 2 "$?" "without jq the guard still blocks (python3 reads the input)"
echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm $HOME/.claude/settings.json\"}}" | GMOS_JQ=/nonexistent/jq bash "$GUARD" >/dev/null 2>&1
check g02 2 "$?" "without jq a Bash delete of the settings file is still blocked"
mkdir -p "$HOME/.god-mode-os" && echo "$T/extra/" > "$HOME/.god-mode-os/protected-paths.txt"
gw "$HOME/.claude/settings.json" | bash "$GUARD" >/dev/null 2>&1
check g03 2 "$?" "a custom path list adds to the defaults, it cannot remove them"
gw "$T/extra/a.txt" | bash "$GUARD" >/dev/null 2>&1
check g04 2 "$?" "a path added in the custom list is protected"
gw "$T/plainproj/a.txt" | bash "$GUARD" >/dev/null 2>&1
check g05 0 "$?" "an ordinary project file is not protected"
rm -f "$HOME/.god-mode-os/protected-paths.txt"

# ---------- push-gate (opt-in) ----------
GATE="$REPO/hooks/discipline/push-gate.sh"
push() { echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$1\"},\"cwd\":\"$T\"}" | bash "$GATE" >/dev/null 2>&1; echo $?; }

check p01 0 "$(push 'git push origin main')" "push-gate is off until switched on"
mkdir -p "$HOME/.god-mode-os" && touch "$HOME/.god-mode-os/push-gate-on"
check p02 2 "$(push 'git push https://github.com/acme/app.git main')" "git push is blocked without an approval"
check p03 2 "$(push 'gh repo create acme/app --public')" "gh repo create is blocked without an approval"
check p04 2 "$(push 'git remote add origin https://github.com/acme/app.git')" "git remote add is blocked without an approval"
check p05 0 "$(push 'git status')" "git status is not a publish command"
check p06 0 "$(push 'git log --oneline -5')" "git log is not a publish command"
echo "TARGET=acme VIS=private" > "$HOME/.god-mode-os/push-approved"
check p07 0 "$(push 'git push https://github.com/acme/app.git main')" "a matching approval lets one push through"
check p08 2 "$(push 'git push https://github.com/acme/app.git main')" "the approval is single-use"
echo "TARGET=other VIS=private" > "$HOME/.god-mode-os/push-approved"
check p09 2 "$(push 'git push https://github.com/acme/app.git main')" "an approval for another owner does not count"
rm -f "$HOME/.god-mode-os/push-approved"
# found by an outside review
check p11 2 "$(push 'git -C repo push origin main')" "git -C <dir> push is blocked"
check p12 2 "$(push 'git -c http.extraHeader=x push')" "git -c <setting> push is blocked"
check p13 2 "$(push '(gh repo create acme/app --public)')" "gh repo create inside brackets is blocked"
check p14 2 "$(push 'git subtree push --prefix dist origin gh-pages')" "git subtree push is blocked"
check p15 2 "$(push 'gh release create v1 dist.zip')" "gh release create is blocked"
check p16 2 "$(push 'gh gist create --public notes.md')" "gh gist create is blocked"
check p17 2 "$(push 'gh api -X POST /user/repos -f name=x')" "gh api with a write method is blocked"
check p18 0 "$(push 'gh api /user/repos')" "gh api read is not a publish command"
check p19 0 "$(push 'gh pr list')" "gh pr list is not a publish command"
echo "TARGET=acme VIS=private" > "$HOME/.god-mode-os/push-approved"
check p20 2 "$(push 'gh repo create acme/app --public --source . --push')" "a private approval does not cover --public"
echo "TARGET=acme VIS=private" > "$HOME/.god-mode-os/push-approved"
check p21 2 "$(push 'gh repo edit acme/app --visibility public')" "a private approval does not cover a switch to public"
echo "TARGET=acme VIS=private" > "$HOME/.god-mode-os/push-approved"
check p22 2 "$(push 'git push https://github.com/acme/app.git main && git push https://github.com/evil/y.git main')" "one approval does not cover two pushes in one command"
echo "TARGET=acme VIS=public" > "$HOME/.god-mode-os/push-approved"
check p23 0 "$(push 'gh repo create acme/app --public')" "a public approval covers --public"
mkdir -p "$T/tworemotes" && git -C "$T/tworemotes" init -q && git -C "$T/tworemotes" remote add origin https://github.com/acme/app.git && git -C "$T/tworemotes" remote add org https://github.com/bigorg/app.git
echo "TARGET=acme VIS=private" > "$HOME/.god-mode-os/push-approved"
echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push org main\"},\"cwd\":\"$T/tworemotes\"}" | bash "$GATE" >/dev/null 2>&1
check p24 2 "$?" "the owner is read from the remote that is named, not from origin"
echo "TARGET=acme VIS=private" > "$HOME/.god-mode-os/push-approved"
touch -t 202001010000 "$HOME/.god-mode-os/push-approved"
check p25 2 "$(push 'git push https://github.com/acme/app.git main')" "an old approval has expired"
[ ! -f "$HOME/.god-mode-os/push-approved" ]; truth p26 $? "and the expired approval is deleted"
rm -f "$HOME/.god-mode-os/push-approved"
# second review round
check p27 2 "$(push 'git -C \"my repo\" push origin main')" "git -C with a quoted folder that has a space is blocked"
check p28 0 "$(push 'gh api graphql -f query=viewer')" "a gh api graphql read is not a publish command"
check p29 0 "$(push 'gh api -X GET search/issues -f q=bug')" "gh api with an explicit GET is not a publish command"
check p30 2 "$(push 'gh pr merge 12 --squash')" "gh pr merge is blocked"
check p31 2 "$(push 'gh api graphql -f query=mutation{addStar}')" "a gh api graphql mutation is blocked"
echo "TARGET=UNKNOWN VIS=private" > "$HOME/.god-mode-os/push-approved"
check p32 2 "$(push 'git push upstream main')" "an approval for UNKNOWN never counts"
rm -f "$HOME/.god-mode-os/push-approved"
touch "$HOME/.claude/.god-mode-disabled"
check p10 0 "$(push 'git push https://github.com/acme/app.git main')" "the kill switch turns the gate off"
rm -f "$HOME/.claude/.god-mode-disabled" "$HOME/.god-mode-os/push-gate-on"

# ---------- dash-guard (opt-in) ----------
DASH="$REPO/hooks/discipline/dash-guard.py"
EM="$(printf '\342\200\224')"
dash() { # dash <file_path> <content>; prints "deny" or "allow"
    out=$(python3 -I -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":sys.argv[2]}}))' "$1" "$2" | python3 -I "$DASH" 2>/dev/null)
    if echo "$out" | grep -q '"permissionDecision": "deny"'; then echo deny; else echo allow; fi
}
[ "$(dash "$T/a.md" "It works $EM mostly.")" = "allow" ]; truth d01 $? "dash-guard is off until switched on"
mkdir -p "$HOME/.god-mode-os" && touch "$HOME/.god-mode-os/dash-guard-on"
[ "$(dash "$T/a.md" "It works $EM mostly.")" = "deny" ]; truth d02 $? "an em dash in a markdown file is denied"
[ "$(dash "$T/a.md" "It works, mostly.")" = "allow" ]; truth d03 $? "plain text passes"
[ "$(dash "$T/a.py" "x = 1  # a $EM b")" = "allow" ]; truth d04 $? "code files are not checked"
[ "$(dash "$T/a.md" "Run \`a $EM b\` now.")" = "allow" ]; truth d05 $? "inline code is not checked"
[ "$(dash "$T/a.md" "> a quoted $EM line")" = "allow" ]; truth d06 $? "quoted lines are not checked"

# ---------- folder-law-reminder ----------
LAW="$REPO/hooks/discipline/folder-law-reminder.sh"
law_in() { echo "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$1\"}}"; }
out=$(law_in "/tmp/notes.txt" | bash "$LAW" 2>/dev/null); rc=$?
check l01 0 "$rc" "a write to /tmp is allowed by default (warning only)"
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | test("/tmp")' >/dev/null 2>&1
truth l02 $? "and the agent is told about it"
law_in "/tmp/notes.txt" | GMOS_FOLDER_LAW=block bash "$LAW" >/dev/null 2>&1
check l03 2 "$?" "with GMOS_FOLDER_LAW=block the same write is blocked"
out=$(law_in "$T/plainproj/notes.txt" | bash "$LAW" 2>/dev/null); rc=$?
[ "$rc" = "0" ] && [ -z "$out" ]; truth l04 $? "a write elsewhere passes silently"

# ---------- capability-manifest ----------
out=$(echo '{}' | bash "$REPO/hooks/capability-manifest.sh" 2>/dev/null)
echo "$out" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart" and (.hookSpecificOutput.additionalContext | length > 20)' >/dev/null 2>&1
truth m01 $? "capability-manifest emits SessionStart context in the documented shape"

# ---------- plugin wiring ----------
jq -e '.name == "god-mode-os" and (.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))' "$REPO/.claude-plugin/plugin.json" >/dev/null 2>&1
truth w01 $? "plugin.json has a name and a version"
jq -e '.plugins[0].name == "god-mode-os" and .owner.name != null' "$REPO/.claude-plugin/marketplace.json" >/dev/null 2>&1
truth w02 $? "marketplace.json lists the plugin"
MISSING=0; BROKEN=0; COUNT=0
while IFS= read -r cmd; do
    COUNT=$((COUNT + 1))
    file=$(printf '%s' "$cmd" | sed -E 's/^[a-z0-9]+ "\$\{CLAUDE_PLUGIN_ROOT\}([^"]+)"$/\1/')
    [ -f "$REPO$file" ] || MISSING=$((MISSING + 1))
    # each wired command must run cleanly on an empty event
    echo '{}' | CLAUDE_PLUGIN_ROOT="$REPO" bash -c "$cmd" >/dev/null 2>&1 || BROKEN=$((BROKEN + 1))
done < <(jq -r '.hooks[][] | .hooks[] | .command' "$REPO/hooks/hooks.json")
[ "$COUNT" -ge 7 ] && [ "$MISSING" = "0" ]; truth w03 $? "every hook the plugin wires exists ($COUNT wired, $MISSING missing)"
[ "$BROKEN" = "0" ]; truth w04 $? "every wired hook runs cleanly on an empty event ($BROKEN broken)"

echo "TOTAL: $TOTAL cases. Failed: $FAILED."
[ "$FAILED" = "0" ]
