#!/bin/bash
# install-guard-cases.sh
# Proves the install guard is neither too loose nor too strict.
# Usage: bash tests/install-guard-cases.sh [path-to-guard]
# Every case runs in a throwaway home folder, so no real file is touched.
# Read cases must pass (reading or only naming a protected path is fine).
# Write cases must block (a protected path is the target of a write, move or delete).
# Pass means: 0 read cases blocked and 0 write cases allowed. Exit 0 on pass, 1 on fail.

HERE="$(cd "$(dirname "$0")" && pwd)"
GUARD="${1:-$HERE/../hooks/discipline/install-guard.sh}"
export GUARD
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

python3 -I - <<'PY'
import json, os, shutil, subprocess, sys, tempfile

guard = os.environ["GUARD"]
home = os.path.realpath(tempfile.mkdtemp(prefix="guard-cases-"))
for d in (".claude/hooks/tests", ".claude/skills", ".claude/plugins", ".claude/commands",
          "work/Outputs", "work/logs/run",
          "work/Archives", "work/Code/x", "work/tasks", "scratch"):
    os.makedirs(os.path.join(home, d))
for f in (".claude/settings.json", ".claude/hooks/install-guard.sh", ".claude/hooks/a.sh",
          ".claude/hooks/heartbeat.log", ".claude/hooks/discipline-toggle.sh",
          "work/x.sh", "work/x.json", "work/x.md",
          "work/logs/a.sh", "scratch/a.sqlite", "work/Code/x/settings.json", "work/Outputs/a.txt"):
    open(os.path.join(home, f), "w").write("x\n")
# Task a skill that really lives in ~/.agents/skills and is reached through a link in ~/.claude/skills.
os.makedirs(os.path.join(home, ".agents/skills/pdf"))
open(os.path.join(home, ".agents/skills/pdf/SKILL.md"), "w").write("x\n")
os.symlink("../../.agents/skills/pdf", os.path.join(home, ".claude/skills/pdf"))
os.makedirs(os.path.join(home, "work/Code/x/.agents/skills"))
os.makedirs(os.path.join(home, ".god-mode-os"))
open(os.path.join(home, ".god-mode-os/push-gate-on"), "w").write("")

def bash(cmd, cwd="@H/work"):
    return {"tool_name": "Bash", "tool_input": {"command": cmd}, "cwd": cwd}

def tool(name, path):
    return {"tool_name": name, "tool_input": {"file_path": path}, "cwd": "@H/work"}

# (id, expected, what it is, hook input). @H stands for the throwaway home folder.
CASES = [
 # ---- read cases: must pass ----
 ("r01", "pass", "list the hooks folder", bash("ls @H/.claude/hooks/")),
 ("r02", "pass", "print the settings file", bash("cat @H/.claude/settings.json")),
 ("r03", "pass", "search the settings file", bash("grep -n install @H/.claude/settings.json")),
 ("r04", "pass", "first lines of a hook log", bash("head -2 @H/.claude/hooks/heartbeat.log")),
 ("r05", "pass", "count lines of the hook scripts", bash("wc -l @H/.claude/hooks/*.sh")),
 ("r06", "pass", "heredoc body names the settings file, target elsewhere",
  bash("cat > @H/work/Outputs/notes-smoke.txt <<'EOF'\nThe settings file @H/.claude/settings.json holds the hooks.\nEOF")),
 ("r07", "pass", "copy inside the scratch folder plus a read of a hook log",
  bash("cp @H/scratch/a.sqlite @H/scratch/b.sqlite; head -2 @H/.claude/hooks/heartbeat.log")),
 ("r08", "pass", "read a hook log, save the count under the work logs",
  bash("grep -c 'FAIL|docker-daemon' @H/.claude/hooks/heartbeat.log | tee @H/work/logs/count.txt")),
 ("r09", "pass", "append a note to a manifest, the note names the hooks folder",
  bash("cat >> @H/work/logs/manifest.md <<'EOF'\n- Undo (Terminal, one line): restore the file kept in ~/.claude/hooks/stop-validator.sh from the fresh copy\nEOF")),
 ("r10", "pass", "seen in real use: make a log folder, save output there, read the guard switch status",
  bash("mkdir -p @H/work/logs/run && cd @H/work/logs/run && echo run > smoke-before.txt 2>&1; tail -5 smoke-before.txt; bash ~/.claude/hooks/discipline-toggle.sh status")),
 ("r11", "pass", "quoted text names a hook, the file written is under Outputs",
  bash("echo \"the guard lives in ~/.claude/hooks/install-guard.sh\" > @H/work/Outputs/n.txt")),
 ("r12", "pass", "copy a hook OUT into the rollback folder (the hook is only read)",
  bash("cp -p @H/.claude/hooks/install-guard.sh @H/work/logs/run/")),
 ("r13", "pass", "jq reads the settings file, result saved under the work logs",
  bash("jq '.hooks' @H/.claude/settings.json > @H/work/logs/hooks.json")),
 ("r14", "pass", "diff a hook against a copy", bash("diff @H/.claude/hooks/a.sh @H/work/logs/a.sh")),
 ("r15", "pass", "date and fingerprint of the settings file",
  bash("stat -f '%Sm' @H/.claude/settings.json; shasum -a 256 @H/.claude/settings.json")),
 ("r16", "pass", "bounded find inside the config folder",
  bash("cd @H/.claude && find . -maxdepth 2 -name '*.sh'")),
 ("r17", "pass", "list the callers of a script, save the list under the work logs",
  bash("grep -n 'some-script' @H/.claude/hooks/*.sh | tee @H/work/logs/callers.txt")),
 ("r18", "pass", "commit message names the hooks folder",
  bash("git -C @H/work/Code/x commit -m \"fix: mention ~/.claude/hooks/ in the docs\"")),
 ("r19", "pass", "delete a file under Outputs, then list the skills folder",
  bash("rm @H/work/Outputs/old.txt; ls @H/.claude/skills/")),
 ("r20", "pass", "print part of a hook with sed (no in-place flag)",
  bash("cat @H/.claude/hooks/install-guard.sh | sed -n 1,20p")),
 ("r21", "pass", "run a test script from the work folder with the guard as an argument, output under logs",
  bash("bash @H/work/logs/run/cases.sh @H/.claude/hooks/install-guard.sh > @H/work/logs/run/out.txt")),
 ("r22", "pass", "quoted text names the rules file, the file written is a note",
  bash("echo \"see CLAUDE.md for the rules\" >> @H/work/Outputs/notes.md")),
 ("r23", "pass", "Edit tool on a project file", tool("Edit", "@H/work/tasks/PROGRESS.md")),
 ("r24", "pass", "Write tool into the scratch folder", tool("Write", "@H/scratch/draft.txt")),
 ("r25", "pass", "rsync a hook OUT into a backup folder", bash("rsync -a @H/.claude/hooks/ @H/work/Archives/hooks-copy/")),
 ("r26", "pass", "python one-liner only reads the settings file", bash("python3 -c \"import json;print(len(json.load(open('@H/.claude/settings.json'))))\"")),
 ("r27", "pass", "find with grep inside the hooks folder", bash("find @H/.claude/hooks -name '*.sh' -exec grep -l needle {} \\;")),
 ("r28", "pass", "xargs with a read verb", bash("ls @H/.claude/hooks/*.sh | xargs wc -l")),
 ("r29", "pass", "move a file inside Outputs while a hook is listed", bash("mv @H/work/Outputs/a.txt @H/work/Outputs/b.txt && ls -la @H/.claude/hooks/a.sh")),
 ("r30", "pass", "python fed by a heredoc only reads the settings file", bash("python3 - <<'EOF'\nimport json\nprint(len(json.load(open('@H/.claude/settings.json'))))\nEOF")),
 ("r31", "pass", "run the case file with the live guard as an argument", bash("cd @H/work/logs/run && bash cases.sh ~/.claude/hooks/install-guard.sh > before.txt 2>&1; echo \"exit $?\"")),
 ("r32", "pass", "fingerprints of hooks saved into the rollback folder", bash("shasum -a 256 @H/.claude/hooks/*.sh > @H/work/logs/run/sums.txt")),
 ("r33", "pass", "touch a file with a variable name outside the config folder, then list skills", bash("touch @H/work/logs/run/\"$PPID\"; ls @H/.claude/skills/")),
 ("r34", "pass", "save a web status code under the work logs, then list the hooks folder", bash("code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:1); echo ok > @H/work/logs/c.txt; ls @H/.claude/hooks/")),
 ("r35", "pass", "copy the settings file OUT to a dated backup under the work logs", bash("cp @H/.claude/settings.json @H/work/logs/settings.bak-$(date +%Y)")),
 ("r36", "pass", "seen in real use: python edits a README elsewhere, the new text names the settings file",
  bash("python3 - \"@H/work/logs/run/README.md\" <<'EOF'\nimport sys\np=sys.argv[1]; s=open(p).read()\ns=s.replace(\"old line\", \"\"\"The settings file is at @H/.claude/settings.json and holds the hooks.\"\"\")\nopen(p,\"w\").write(s)\nEOF")),
 # ---- linked skills folder, read cases: must pass ----
 ("r37", "pass", "print a skill file at its real path", bash("cat @H/.agents/skills/pdf/SKILL.md")),
 ("r38", "pass", "print a skill file through the link", bash("cat @H/.claude/skills/pdf/SKILL.md")),
 ("r39", "pass", "list the real skills folder", bash("ls -la @H/.agents/skills/")),
 ("r40", "pass", "copy a skill file OUT of the real folder into the rollback folder", bash("cp -p @H/.agents/skills/pdf/SKILL.md @H/work/logs/run/")),
 ("r41", "pass", "search the real folder, save the list under the work logs", bash("grep -rl name @H/.agents/skills/pdf | tee @H/work/logs/found.txt")),
 ("r42", "pass", "note written under Outputs, the heredoc body names the real folder", bash("cat > @H/work/Outputs/n392.txt <<'EOF'\nSkills really live in ~/.agents/skills/ and are linked.\nEOF")),
 ("r43", "pass", "python edits a README elsewhere, the new text names the real folder in a sentence",
  bash("python3 - \"@H/work/logs/run/README.md\" <<'EOF'\nimport sys\np=sys.argv[1]; s=open(p).read()\ns=s.replace(\"old line\", \"\"\"The skills live in @H/.agents/skills and are linked from the config folder.\"\"\")\nopen(p,\"w\").write(s)\nEOF")),
 ("r44", "pass", "write into a project folder that has its own .agents/skills", bash("echo x > @H/work/Code/x/.agents/skills/note.md")),
 ("r45", "pass", "Write tool into a project's own .agents/skills", tool("Write", "@H/work/Code/x/.agents/skills/a/SKILL.md")),
 ("r46", "pass", "tar the real folder OUT into a backup under the work folder", bash("tar -cf @H/work/Archives/agents-skills.tar -C @H/.agents skills")),
 # ---- write cases: must block ----
 ("w01", "block", "delete a hook", bash("rm @H/.claude/hooks/install-guard.sh")),
 ("w02", "block", "append to the settings file", bash("echo x >> @H/.claude/settings.json")),
 ("w03", "block", "copy a file into the hooks folder (full target name)", bash("cp @H/work/x.sh @H/.claude/hooks/x.sh")),
 ("w04", "block", "copy a file into the hooks folder (folder as target)", bash("cp @H/work/x.sh @H/.claude/hooks/")),
 ("w05", "block", "move a hook out of the hooks folder", bash("mv @H/.claude/hooks/install-guard.sh @H/work/Archives/")),
 ("w06", "block", "in-place sed on a hook", bash("sed -i '' 's/block/allow/' @H/.claude/hooks/install-guard.sh")),
 ("w07", "block", "create the kill switch file", bash("touch @H/.claude/.god-mode-disabled")),
 ("w10", "block", "tee into a hook", bash("cat @H/work/x.sh | tee -a @H/.claude/hooks/a.sh")),
 ("w11", "block", "cd into the hooks folder, then delete by short name", bash("cd @H/.claude/hooks && rm install-guard.sh")),
 ("w12", "block", "working folder is the hooks folder, write by short name", bash("echo x > new-hook.sh", cwd="@H/.claude/hooks")),
 ("w13", "block", "delete the whole config folder", bash("rm -rf @H/.claude")),
 ("w14", "block", "link a file into the hooks folder", bash("ln -s @H/work/x.sh @H/.claude/hooks/x.sh")),
 ("w15", "block", "rsync into the skills folder", bash("rsync -a @H/work/Code/x/ @H/.claude/skills/")),
 ("w16", "block", "git clone into the skills folder", bash("git clone https://example.com/x.git @H/.claude/skills/x")),
 ("w17", "block", "install an MCP server", bash("claude mcp add foo -- npx foo")),
 ("w18", "block", "install a plugin", bash("claude plugin install foo")),
 ("w19", "block", "delete a hook through a variable", bash("D=@H/.claude/hooks; rm \"$D/install-guard.sh\"")),
 ("w20", "block", "python one-liner writes the settings file", bash("python3 -c \"open('@H/.claude/settings.json','w').write('{}')\"")),
 ("w21", "block", "delete a hook inside bash -c", bash("bash -c 'rm @H/.claude/hooks/a.sh'")),
 ("w22", "block", "python fed by a heredoc writes the settings file", bash("python3 - <<'EOF'\nopen('@H/.claude/settings.json','w').write('{}')\nEOF")),
 ("w23", "block", "overwrite a rules file in the work folder", bash("echo x > @H/work/CLAUDE.md")),
 ("w24", "block", "copy over the global rules file, tilde path", bash("cp @H/work/x.md ~/.claude/CLAUDE.md")),
 ("w25", "block", "delete a hook through a path with dot-dot", bash("rm @H/work/../.claude/hooks/a.sh")),
 ("w26", "block", "find with delete inside the hooks folder", bash("find @H/.claude/hooks -name '*.bak' -delete")),
 ("w27", "block", "xargs rm fed from the hooks folder", bash("ls @H/.claude/hooks/*.sh | xargs rm")),
 ("w28", "block", "remove the run permission from a hook", bash("chmod -x @H/.claude/hooks/install-guard.sh")),
 ("w29", "block", "Edit tool on a hook", tool("Edit", "@H/.claude/hooks/install-guard.sh")),
 ("w30", "block", "Write tool on the settings file", tool("Write", "@H/.claude/settings.json")),
 ("w31", "block", "Edit tool on a rules file", tool("Edit", "@H/work/CLAUDE.md")),
 ("w32", "block", "download straight into the hooks folder", bash("curl -o @H/.claude/hooks/x.sh https://example.com/x.sh")),
 ("w33", "block", "sandbox override flag", bash("echo run with dangerouslyOverrideSandbox")),
 ("w34", "block", "redirect with no space before the settings file", bash("echo x >@H/.claude/settings.json")),
 ("w35", "block", "delete a hook through the home variable", bash("rm \"$HOME/.claude/hooks/a.sh\"")),
 ("w36", "block", "delete a hook, folder name in capitals (the disk ignores case)", bash("rm @H/.CLAUDE/hooks/a.sh")),
 ("w38", "block", "switch the guards off with the toggle script (full)", bash("bash @H/.claude/hooks/discipline-toggle.sh off")),
 ("w39", "block", "make a new skill folder", bash("mkdir -p @H/.claude/skills/new-skill")),
 ("w40", "block", "heredoc written into a hook", bash("cat > @H/.claude/hooks/a.sh <<'EOF'\nexit 0\nEOF")),
 ("w41", "block", "ed script fed by a heredoc rewrites the settings file", bash("ed -s @H/.claude/settings.json <<'EOF'\n,s/a/b/\nw\nEOF")),
 ("w42", "block", "fake heredoc opener inside quotes hides a delete", bash("cat @H/work/x.md \"<<E\"\nrm @H/.claude/hooks/a.sh\nE")),
 ("w43", "block", "heredoc body runs a command that deletes a hook", bash("cat > @H/work/Outputs/n.txt <<EOF\n$(rm @H/.claude/hooks/a.sh)\nEOF")),
 ("w44", "block", "git checkout rewrites a hook from the config folder", bash("git -C @H/.claude checkout -- hooks/install-guard.sh")),
 ("w45", "block", "pushd into the hooks folder, then delete by short name", bash("pushd @H/.claude/hooks; rm a.sh")),
 ("w46", "block", "loop deletes every hook", bash("for f in @H/.claude/hooks/*.sh; do rm \"$f\"; done")),
 ("w47", "block", "osascript runs a shell delete of a hook", bash("osascript -e 'do shell script \"rm @H/.claude/hooks/a.sh\"'")),
 ("w48", "block", "save a file, then move it over the settings file", bash("jq '.x=1' @H/.claude/settings.json > @H/work/x.json && mv @H/work/x.json @H/.claude/settings.json")),
 ("w49", "block", "recursive permission change on the whole config folder", bash("chmod -R 777 @H/.claude")),
 ("w50", "block", "copy a settings file into the config folder (folder as target)", bash("cp @H/work/Code/x/settings.json @H/.claude/")),
 ("w51", "block", "delete a hook through an exported variable", bash("export D=@H/.claude/hooks; rm $D/a.sh")),
 ("w52", "block", "find with exec rm inside the hooks folder", bash("find @H/.claude/hooks -name '*.bak' -exec rm {} \\;")),
 ("w53", "block", "copy files named by a sub-command into the hooks folder", bash("cp $(ls @H/work/*.sh) @H/.claude/hooks/")),
 ("w54", "block", "delete a hook inside a quoted sub-command", bash("echo \"$(rm @H/.claude/hooks/a.sh)\"")),
 ("w55", "block", "create a file with a variable name inside the hooks folder", bash("touch @H/.claude/hooks/\"$X\"")),
 ("w56", "block", "copy onto a config file whose name ends in a variable", bash("cp @H/work/x.json @H/.claude/set$X")),
 ("w57", "block", "python fed by a heredoc starts a shell delete of a hook", bash("python3 - <<'EOF'\nimport subprocess\nsubprocess.run(\"rm @H/.claude/hooks/a.sh\", shell=True)\nEOF")),
 ("w58", "block", "python builds the hook path from parts and writes it", bash("python3 - <<'EOF'\nimport os\np=os.path.join(os.path.expanduser('~'),'.claude','hooks','a.sh')\nopen(p,'w').write('x')\nEOF")),
 # ---- linked skills folder, write cases: must block ----
 ("w59", "block", "Edit tool on a skill file through the link", tool("Edit", "@H/.claude/skills/pdf/SKILL.md")),
 ("w60", "block", "Edit tool on a skill file at its real path", tool("Edit", "@H/.agents/skills/pdf/SKILL.md")),
 ("w61", "block", "Write tool makes a new skill in the real folder", tool("Write", "@H/.agents/skills/new-skill/SKILL.md")),
 ("w62", "block", "append to a skill file through the link", bash("echo x >> @H/.claude/skills/pdf/SKILL.md")),
 ("w63", "block", "append to a skill file at its real path", bash("echo x >> @H/.agents/skills/pdf/SKILL.md")),
 ("w64", "block", "in-place sed on a skill file at its real path", bash("sed -i '' 's/a/b/' @H/.agents/skills/pdf/SKILL.md")),
 ("w65", "block", "delete a skill folder at its real path", bash("rm -rf @H/.agents/skills/pdf")),
 ("w66", "block", "make a new skill folder in the real folder", bash("mkdir -p @H/.agents/skills/new-skill")),
 ("w67", "block", "copy a file into the real folder (folder as target)", bash("cp @H/work/x.md @H/.agents/skills/pdf/")),
 ("w68", "block", "cd into the real folder, then write by short name", bash("cd @H/.agents/skills/pdf && echo x > SKILL.md")),
 ("w69", "block", "delete the whole .agents folder", bash("rm -rf @H/.agents")),
 ("w70", "block", "python one-liner writes a skill file at its real path", bash("python3 -c \"open('@H/.agents/skills/pdf/SKILL.md','w').write('x')\"")),
 ("w71", "block", "move the real skills folder away", bash("mv @H/.agents/skills @H/work/Archives/")),
 ("w72", "block", "append to a skill file, tilde path", bash("echo x >> ~/.agents/skills/pdf/SKILL.md")),
 ("w73", "block", "delete a skill file, folder name in capitals (the disk ignores case)", bash("rm @H/.AGENTS/skills/pdf/SKILL.md")),
 ("w74", "block", "git clone into the real folder", bash("git clone https://example.com/x.git @H/.agents/skills/x")),
 ("w75", "block", "link a file into the real folder", bash("ln -s @H/work/x.md @H/.agents/skills/x.md")),
 ("w76", "block", "python builds the real path from parts and writes it", bash("python3 - <<'EOF'\nimport os\np=os.path.join(os.path.expanduser('~'),'.agents','skills','pdf','SKILL.md')\nopen(p,'w').write('x')\nEOF")),
 ("w77", "block", "unpack an archive into the real folder", bash("tar -xf @H/work/Archives/a.tar -C @H/.agents/skills")),
 # ---- found by an outside review: more read cases that must pass ----
 ("r47", "pass", "print a protected path with echo", bash("echo @H/.claude/settings.json")),
 ("r48", "pass", "test whether the settings file exists", bash("[ -f @H/.claude/settings.json ] && echo yes")),
 ("r49", "pass", "loop over the hooks and count lines", bash("for f in @H/.claude/hooks/*.sh; do wc -l \"$f\"; done")),
 ("r50", "pass", "copy the whole hooks folder OUT to a backup", bash("cp -r @H/.claude/hooks @H/work/Archives/")),
 ("r51", "pass", "archive the config folder OUT to a backup", bash("tar -czf @H/work/Archives/b.tgz -C @H .claude")),
 ("r52", "pass", "read the settings file through a timeout wrapper", bash("timeout 5 cat @H/.claude/settings.json")),
 ("r53", "pass", "print the guard's own path list", bash("cat @H/.god-mode-os/protected-paths.txt")),
 ("r54", "pass", "braces in a path outside the config folder", bash("mkdir -p @H/work/{a,b} && cp @H/work/x.md @H/work/{a,b}/ 2>/dev/null; ls @H/.claude/hooks/")),
 ("r55", "pass", "download into the work folder with bundled flags, then list hooks", bash("curl -fsSLo @H/work/x.sh https://example.com/x.sh; ls @H/.claude/hooks/")),
 ("r56", "pass", "unpack an archive inside the work folder", bash("cd @H/work && tar xzf @H/work/Archives/b.tgz")),
 # ---- found by an outside review: write cases that must block ----
 ("w80", "block", "braces: delete two config folders at once", bash("rm -rf @H/.claude/{hooks,skills}")),
 ("w81", "block", "braces: restore idiom that overwrites the settings file", bash("cp @H/.claude/settings.json{.bak,}")),
 ("w82", "block", "braces: rename the settings file away", bash("mv @H/.claude/settings.json{,.old}")),
 ("w83", "block", "braces: create a file in two config folders", bash("touch @H/.claude/{hooks,skills}/x")),
 ("w84", "block", "braces: make config folders", bash("mkdir -p @H/.claude/{hooks,skills,commands}")),
 ("w85", "block", "curl with bundled flags into the hooks folder", bash("curl -fsSLo @H/.claude/hooks/x.sh https://example.com/x.sh")),
 ("w86", "block", "wget with bundled flags into the hooks folder", bash("wget -qO @H/.claude/hooks/x.sh https://example.com/x.sh")),
 ("w87", "block", "curl with an output folder inside the config", bash("curl --output-dir @H/.claude/hooks -O https://example.com/x.sh")),
 ("w88", "block", "tar with the folder flag first, into the hooks folder", bash("tar -C @H/.claude/hooks -xzf @H/work/Archives/a.tgz")),
 ("w89", "block", "tar unpacked over the whole config folder", bash("tar -C @H/.claude -xzf @H/work/Archives/a.tgz")),
 ("w90", "block", "cd into the config folder, then unpack a tar there", bash("cd @H/.claude && tar xzf @H/work/Archives/a.tgz")),
 ("w91", "block", "cd into the config folder, then unzip there", bash("cd @H/.claude && unzip -o @H/work/Archives/a.zip")),
 ("w92", "block", "cd into the config folder, then apply a patch", bash("cd @H/.claude && patch -p1 < @H/work/fix.patch")),
 ("w93", "block", "copy many files over the config folder (glob source)", bash("cp -r @H/work/Code/x/* @H/.claude/")),
 ("w94", "block", "copy a folder's contents over the config folder (dot source)", bash("cp -R @H/work/Code/x/. @H/.claude/")),
 ("w95", "block", "cd into the config folder, then copy many files to here", bash("cd @H/.claude && cp -r @H/work/Code/x/* .")),
 ("w96", "block", "gh repo clone into the skills folder", bash("gh repo clone someone/skill @H/.claude/skills/skill")),
 ("w97", "block", "GNU sed in place on the settings file", bash("gsed -i 's/a/b/' @H/.claude/settings.json")),
 ("w98", "block", "copy into the hooks folder through a timeout wrapper", bash("timeout 10 cp @H/work/x.sh @H/.claude/hooks/")),
 ("w99", "block", "copy into the hooks folder through sudo with a user", bash("sudo -u root cp @H/work/x.sh @H/.claude/hooks/x.sh")),
 ("w100", "block", "python run through a wrapper writes the settings file", bash("uv run python -c \"open('@H/.claude/settings.json','w').write('{}')\"")),
 ("w101", "block", "php one-liner writes the settings file", bash("php -r 'file_put_contents(\"@H/.claude/settings.json\", \"x\");'")),
 ("w102", "block", "an unknown tool is pointed straight at the settings file", bash("plutil -replace k -string v @H/.claude/settings.json")),
 ("w103", "block", "overwrite the guard's own path list", bash("echo /nonexistent > @H/.god-mode-os/protected-paths.txt")),
 ("w104", "block", "delete the push gate switch", bash("rm @H/.god-mode-os/push-gate-on")),
 ("w105", "block", "Write tool on the guard's own path list", tool("Write", "@H/.god-mode-os/protected-paths.txt")),
 # ---- second review round: harmless commands that must pass ----
 ("r57", "pass", "print the settings file as a property list", bash("plutil -p @H/.claude/settings.json")),
 ("r58", "pass", "list hooks with a modern ls", bash("eza -la @H/.claude/hooks")),
 ("r59", "pass", "find files in hooks with fd", bash("fd . @H/.claude/hooks")),
 ("r60", "pass", "count lines of code in hooks", bash("cloc @H/.claude/hooks")),
 ("r61", "pass", "render a skill file in the terminal", bash("glow @H/.claude/skills/pdf/SKILL.md")),
 ("r62", "pass", "list extended attributes of the settings file", bash("xattr -l @H/.claude/settings.json")),
 ("r63", "pass", "check the formatting of a project rules file", bash("npx prettier --check CLAUDE.md")),
 ("r64", "pass", "convert a project rules file to another file", bash("pandoc CLAUDE.md -o out.html")),
 ("r65", "pass", "a notification whose text names the rules file", bash("terminal-notifier -message \"CLAUDE.md reviewed\"")),
 ("r66", "pass", "rsync one file into the home folder", bash("rsync -av @H/work/x.md @H/")),
 ("r67", "pass", "sort the settings file to the screen", bash("sort @H/.claude/settings.json")),
 ("r68", "pass", "lint the rules file with other files", bash("npx markdownlint-cli2 README.md CLAUDE.md")),
 # ---- second review round: write cases that must block ----
 ("w106", "block", "restore idiom: copy a folder's contents over the config folder (trailing slash)", bash("cp -R @H/work/Code/x/ @H/.claude/")),
 ("w107", "block", "copy a backup of the config folder into the home folder (merges over it)", bash("cp -R @H/work/Archives/.claude @H/")),
 ("w108", "block", "patch with a target folder inside the config", bash("patch -p1 -d @H/.claude < @H/work/fix.patch")),
 ("w109", "block", "python through poetry writes the settings file", bash("poetry run python -c \"open('@H/.claude/settings.json','w').write('{}')\"")),
 ("w110", "block", "a formatter rewrites every hook (glob)", bash("shfmt -w @H/.claude/hooks/*.sh")),
 ("w111", "block", "yq edits the settings file in place", bash("yq -i '.a = 1' @H/.claude/settings.json")),
 ("w112", "block", "sort writes back over the settings file", bash("sort -o @H/.claude/settings.json @H/.claude/settings.json")),
 ("w113", "block", "xxd writes a binary into the hooks folder", bash("xxd -r @H/work/dump.hex @H/.claude/hooks/x.sh")),
 ("w114", "block", "base64 decodes into the hooks folder", bash("base64 -d -i @H/work/in.b64 -o @H/.claude/hooks/x.sh")),
 ("w115", "block", "zip that deletes its sources, pointed at hooks", bash("zip -rm @H/work/old.zip @H/.claude/hooks")),
 ("w116", "block", "curl with the output path glued to the flag", bash("curl -o@H/.claude/hooks/x.sh https://example.com/x.sh")),
 ("w117", "block", "an unknown tool with an output flag into hooks", bash("some-tool --out=@H/.claude/hooks/x.sh")),
 ("w118", "block", "a formatter rewrites a project rules file", bash("npx prettier --write CLAUDE.md")),
 ("w119", "block", "awk edits the settings file in place", bash("gawk -i inplace '{print}' @H/.claude/settings.json")),
 ("w120", "block", "clear extended attributes on the settings file", bash("xattr -c @H/.claude/settings.json")),
 ("w121", "block", "rsync a folder's contents over the config folder", bash("rsync -a @H/work/Code/x/ @H/.claude/")),
 ("w122", "block", "awk program redirects its output into the settings file", bash("awk '{print > \"@H/.claude/settings.json\"}' notes.txt")),
 ("w123", "block", "awk program runs a shell command on the settings file", bash("awk 'BEGIN{system(\"rm @H/.claude/settings.json\")}'")),
 ("w124", "block", "sed w command writes into the settings file", bash("sed -n 'w @H/.claude/settings.json' notes.txt")),
 ("w125", "block", "zip creates its archive inside the skills folder", bash("zip @H/.claude/skills/x.zip notes.txt")),
 ("w126", "block", "write to a variable that was filled from a command naming the settings file", bash("F=$(echo @H/.claude/settings.json); echo x > \"$F\"")),
 ("w127", "block", "awk writes to a file name handed in with -v", bash('awk -v f=@H/.claude/settings.json "{print > f}" notes.txt')),
 ("w128", "block", "awk runs an unseen script file on the settings file", bash("awk -f prog.awk @H/.claude/settings.json")),
 ("w129", "block", "sed e command runs a shell command on the settings file", bash("sed -n '1e rm @H/.claude/settings.json' notes.txt")),
 ("w130", "block", "sed substitute with a w flag writes into the settings file", bash("sed 's/a/b/w @H/.claude/settings.json' notes.txt")),
 ("w131", "block", "sed runs an unseen script file on the settings file", bash("sed -f edit.sed @H/.claude/settings.json")),
 ("w132", "block", "zip writes its output archive into the skills folder with -O", bash("zip notes.zip a.txt -O @H/.claude/skills/x.zip")),
 ("w133", "block", "zip test command option runs a shell command on the settings file", bash('zip -T -TT "rm @H/.claude/settings.json" notes.zip a.txt')),
 ("w134", "block", "zip with a temp folder option still creates its archive in the skills folder", bash("zip -b @H/tmp @H/.claude/skills/x.zip notes.txt")),
 ("w135", "block", "sed w command with the file name in a variable", bash('F=@H/.claude/settings.json; sed -n "w $F" notes.txt')),
 ("r72", "pass", "awk reads the settings file and writes a copy of one column elsewhere", bash("awk '{print $1 > \"out.txt\"}' @H/.claude/settings.json")),
 ("r73", "pass", "sed with two plain substitutions prints the settings file", bash("sed -e 's/a/b/' -e 's/c/d/' @H/.claude/settings.json")),
 ("r74", "pass", "zip the skills folder into a backup folder, leaving out logs", bash("zip -r @H/backup/skills.zip @H/.claude/skills -x '*.log'")),
 ("w136", "block", "sed script glued to its -e option writes into the settings file", bash("sed -n -e'w @H/.claude/settings.json' notes.txt")),
 ("w137", "block", "sed script given with the long expression option writes into the settings file", bash("sed -n --expression='w @H/.claude/settings.json' notes.txt")),
 ("w138", "block", "awk redirect after a string that holds a semicolon", bash("awk '{printf(\"%s;\", $0) > \"@H/.claude/settings.json\"}' notes.txt")),
 ("w139", "block", "zip output option placed after an exclude list", bash("zip notes.zip a.txt -x '*.log' -O @H/.claude/skills/x.zip")),
 ("w140", "block", "awk file name handed in as an operand assignment", bash('awk "{print > f}" f=@H/.claude/settings.json notes.txt')),
 ("w141", "block", "awk file name handed in with the long assign option", bash('awk --assign f=@H/.claude/settings.json "{print > f}" notes.txt')),
 ("w142", "block", "awk script file glued to its -f option", bash("awk -fprog.awk @H/.claude/settings.json")),
 ("w143", "block", "gawk in-place option glued to its value", bash("gawk -iinplace '{print}' @H/.claude/settings.json")),
 ("w144", "block", "gawk in-place option in its long form with a separate value", bash("gawk --include inplace '{print}' @H/.claude/settings.json")),
 ("w145", "block", "gawk loads an extension while pointed at the settings file", bash("gawk --load=inplace '{print}' @H/.claude/settings.json")),
 ("w146", "block", "awk long assign option shortened to a prefix", bash('awk --ass f=@H/.claude/settings.json "{print > f}" notes.txt')),
 ("r75", "pass", "awk with a field separator reads the settings file", bash("awk -F: '{print $1}' @H/.claude/settings.json")),
 ("r76", "pass", "awk with a plain number variable reads the settings file", bash("awk -v n=3 '$1 > n' @H/.claude/settings.json")),
 ("w147", "block", "mawk runs a script through its -W option", bash("mawk -W exec prog.awk @H/.claude/settings.json")),
 ("w148", "block", "gawk script file option bundled behind another short option", bash("gawk -bf prog.awk @H/.claude/settings.json")),
 ("w149", "block", "awk variable option bundled and glued to a protected file name", bash('gawk -bvf=@H/.claude/settings.json "{print > f}" notes.txt')),
 ("r77", "pass", "awk with separator options reads the settings file", bash("awk -F, -v OFS=';' '{print $2}' @H/.claude/settings.json")),
 ("r78", "pass", "gawk in byte mode reads the settings file", bash("gawk -b '{print}' @H/.claude/settings.json")),
 ("w150", "block", "gawk pretty-print output glued to -o lands on the settings file", bash("gawk -o@H/.claude/settings.json '{print}' notes.txt")),
 ("w151", "block", "gawk dumps its variables into the settings file", bash("gawk --dump-variables=@H/.claude/settings.json 'BEGIN{}'")),
 ("w152", "block", "gawk writes its profile into the hooks folder", bash("gawk --profile=@H/.claude/hooks/x.sh '{print}' notes.txt")),
 ("w153", "block", "gawk dump option bundled behind another short option", bash("gawk -bd@H/.claude/settings.json 'BEGIN{}'")),
 ("r79", "pass", "gawk pretty-prints to another folder while reading the settings file", bash("gawk -o@H/out/pp.awk '{print}' @H/.claude/settings.json")),
 ("w154", "block", "gawk variable dump with its default file name, run inside the hooks folder", bash("cd @H/.claude/hooks && gawk -d 'BEGIN{}'")),
 ("w155", "block", "gawk profile with its default file name, run inside the hooks folder", bash("cd @H/.claude/hooks && gawk --profile '{print}' notes.txt")),
 ("r80", "pass", "gawk variable dump with its default file name in an ordinary folder", bash("gawk -d 'BEGIN{}'")),
 ("w156", "block", "make a link to the config folder, then write through the link", bash("ln -s @H/.claude @H/work/c && echo x > @H/work/c/settings.json")),
 ("w157", "block", "find from the home folder runs rm on what it finds", bash("find @H -name settings.json -exec rm {} \\;")),
 ("w158", "block", "python writes to a skill path that has a space in it", bash("python3 -c \"open('@H/.claude/skills/my skill/x.md','w').write('a')\"")),
 ("r81", "pass", "find in a work folder runs rm on temp files", bash("find @H/work -name '*.tmp' -exec rm {} \\;")),
 ("r82", "pass", "a link between two ordinary folders", bash("ln -s @H/work/a @H/work/b")),
 ("w159", "block", "link to the config folder using the target-folder option", bash("ln -s -t @H/work @H/.claude")),
 ("w160", "block", "link to the hooks folder with the target-folder option glued to other flags", bash("ln -st @H/work @H/.claude/hooks")),
 ("w161", "block", "hard link to the settings file made with cp", bash("cp -l @H/.claude/settings.json @H/work/s.json")),
 ("w162", "block", "find with a leading option, from the home folder, runs rm", bash("find -L @H -name settings.json -exec rm {} \\;")),
 ("w163", "block", "find with its start folder given through -f runs rm", bash("find -f @H -name settings.json -exec rm {} \\;")),
 ("r83", "pass", "hard link between two ordinary files", bash("cp -l @H/work/a.txt @H/work/b.txt")),
 ("r84", "pass", "find with a leading option in a work folder runs rm on temp files", bash("find -L @H/work -name '*.tmp' -exec rm {} \\;")),
 ("r69", "pass", "awk comparison with a greater-than sign while reading the settings file", bash("awk '$1 > 3' @H/.claude/settings.json")),
 ("r70", "pass", "sed prints lines of the settings file", bash("sed -n '1,5p' @H/.claude/settings.json")),
 ("r71", "pass", "zip a copy of the skills folder into another folder", bash("zip -r @H/backup/skills.zip @H/.claude/skills")),
]

env = dict(os.environ)
env["HOME"] = home
for k in ("GMOS_HOME", "GMOS_KILL_SWITCH", "GMOS_PROTECTED_PATHS", "GMOS_EVENT_LOG"):
    env.pop(k, None)
env.pop("GMOS_ADMIN_OVERRIDE", None)

read_blocked = write_allowed = 0
for cid, expected, what, inp in CASES:
    raw = json.dumps(inp).replace("@H", home)
    try:
        p = subprocess.run(["bash", guard], input=raw, capture_output=True, text=True, env=env, timeout=10)
        got = "block" if p.returncode == 2 else ("pass" if p.returncode == 0 else "error-%d" % p.returncode)
    except subprocess.TimeoutExpired:
        got = "timeout"
    ok = got == expected
    if not ok and expected == "pass":
        read_blocked += 1
    if not ok and expected == "block":
        write_allowed += 1
    print("%s  %s  expected %-5s got %-8s %s" % ("OK  " if ok else "FAIL", cid, expected, got, what))

shutil.rmtree(home, ignore_errors=True)
n_read = sum(1 for c in CASES if c[1] == "pass")
n_write = len(CASES) - n_read
print("TOTAL: %d cases (%d read, %d write). Read cases blocked: %d. Write cases allowed: %d." %
      (len(CASES), n_read, n_write, read_blocked, write_allowed))
sys.exit(0 if read_blocked == 0 and write_allowed == 0 else 1)
PY
