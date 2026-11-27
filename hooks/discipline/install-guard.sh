#!/bin/bash
# install-guard.sh : PreToolUse hook
# Blocks tool calls that write to, move, delete or change permissions on Claude Code config paths.
#
# The Bash check looks at WHERE a command writes. It blocks when a protected path is the
# target of a write, move, delete or permission change. It does not block when a protected
# path is only read, or only named inside quoted text or a heredoc body.
# Case file: tests/install-guard-cases.sh (read cases must pass, write cases must block).
# If the target check cannot run (python missing or crashed), the older and stricter rule
# "any write verb plus any protected path" decides. A failure makes the guard stricter, never looser.
#
# Honors the kill switch at ~/.claude/.god-mode-disabled
# Honors GMOS_ADMIN_OVERRIDE=1 when Claude Code itself was started with it (all hooks off for that session).
# Exit 0 = allow. Exit 2 + stderr = block (Claude Code shows stderr to the model).
#
# Config: ~/.god-mode-os/protected-paths.txt, one path per line, added to the built-in list.
# GMOS_PROTECT_CLAUDE_MD=0 stops treating every CLAUDE.md as protected.

set -u
[ -z "${HOME:-}" ] && exit 0

GMOS_HOME="${GMOS_HOME:-$HOME/.god-mode-os}"
KILL_SWITCH="${GMOS_KILL_SWITCH:-$HOME/.claude/.god-mode-disabled}"
EVENT_LOG="${GMOS_EVENT_LOG:-$GMOS_HOME/events.jsonl}"
CONFIG_FILE="${GMOS_PROTECTED_PATHS:-$GMOS_HOME/protected-paths.txt}"
PROTECT_CLAUDE_MD="${GMOS_PROTECT_CLAUDE_MD:-1}"

# The hook shell does not always have Homebrew on PATH (jq often lives there).
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

log_event() {
    if [ -d "$GMOS_HOME" ] || mkdir -p "$GMOS_HOME" 2>/dev/null; then
        echo "{\"ts\":$(date +%s),\"hook\":\"install-guard\",\"event\":\"$1\",\"detail\":$2}" >> "$EVENT_LOG" 2>/dev/null
    fi
}

# 1. Kill switch
[ -f "$KILL_SWITCH" ] && exit 0

# 2. Admin override
[ "${GMOS_ADMIN_OVERRIDE:-}" = "1" ] && exit 0

# 3. Read JSON input from stdin
INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

# Reading the hook input: jq when it is there, python3 when it is not. Only when both are
# missing does the call pass unchecked, and then the hook says so.
JQ="${GMOS_JQ:-jq}"
if command -v "$JQ" >/dev/null 2>&1; then
    field() { echo "$INPUT" | "$JQ" -r "$1 // empty" 2>/dev/null; }
    json_string() { printf '%s' "$1" | "$JQ" -Rs .; }
elif command -v python3 >/dev/null 2>&1; then
    field() {
        GUARD_INPUT="$INPUT" python3 -I -c '
import json, os, sys
d = json.loads(os.environ["GUARD_INPUT"])
cur = d
for part in sys.argv[1].strip(".").split("."):
    cur = (cur or {}).get(part) if isinstance(cur, dict) else None
print(cur if isinstance(cur, str) else "")' "$1" 2>/dev/null
    }
    json_string() { python3 -I -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$1" 2>/dev/null; }
else
    >&2 echo "install-guard: neither jq nor python3 found, this tool call was NOT checked (warning only)"
    log_event "gate-error" "\"jq and python3 missing, call not checked\""
    exit 0
fi

TOOL_NAME=$(field '.tool_name')
[ -z "$TOOL_NAME" ] && exit 0

# 4. Protected paths. The defaults always apply. Lines in the config file ADD to them, so
#    nothing written into that file can take a default away.
PROTECTED_PATHS=(
    "$HOME/.claude.json"
    "$HOME/.claude/settings.json"
    "$HOME/.claude/settings.local.json"
    "$HOME/.claude/hooks/"
    "$HOME/.claude/skills/"
    "$HOME/.agents/skills/"
    "$HOME/.claude/plugins/"
    "$HOME/.claude/commands/"
)
if [ -f "$CONFIG_FILE" ]; then
    while IFS= read -r line; do
        line="${line%%#*}"
        line="${line## }"; line="${line%% }"
        [ -z "$line" ] && continue
        line="${line/#\~/$HOME}"
        line="${line//\$HOME/$HOME}"
        PROTECTED_PATHS+=("$line")
    done < "$CONFIG_FILE"
fi
# The guard's own switches are always protected: the agent must not turn its guard off or
# rewrite the list of what is guarded.
PROTECTED_PATHS+=(
    "$KILL_SWITCH"
    "$CONFIG_FILE"
    "$GMOS_HOME/forbidden-write-paths.txt"
    "$GMOS_HOME/push-gate-on"
    "$GMOS_HOME/dash-guard-on"
)

is_protected_path() {
    local target="$1"
    for path in "${PROTECTED_PATHS[@]}"; do
        if [[ "$target" == *"$path"* ]]; then
            return 0
        fi
    done
    if [ "$PROTECT_CLAUDE_MD" != "0" ] && [[ "$target" == *"CLAUDE.md"* ]]; then
        return 0
    fi
    return 1
}

block() {
    local reason="$1"
    log_event "block" "$(json_string "$reason")"
    >&2 echo "INSTALL/CONFIG GUARD BLOCK: $reason"
    >&2 echo ""
    >&2 echo "This hook prevents accidental writes to Claude Code config paths."
    >&2 echo "It is a safety gate, not a missing capability. To proceed legitimately:"
    >&2 echo "  1. Tell the user what you want to change and why."
    >&2 echo "  2. If they agree, THEY make the change, or they switch the guards off for a moment:"
    >&2 echo "     touch $KILL_SWITCH    # guards off"
    >&2 echo "     rm $KILL_SWITCH       # guards on"
    >&2 echo "  Putting GMOS_ADMIN_OVERRIDE=1 in front of a command does not work: the variable"
    >&2 echo "  only counts when Claude Code itself was started with it."
    exit 2
}

# The older rule, kept as the fallback when the target check cannot run.
legacy_bash_check() {
    local CMD="$1"
    local CMD_EXPANDED="${CMD//\~/$HOME}"
    CMD_EXPANDED="${CMD_EXPANDED//\$HOME/$HOME}"
    if echo "$CMD" | grep -qE '(npx|bunx|pnpx|pnpm[[:space:]]+dlx|npm[[:space:]]+exec)[[:space:]]+(-y[[:space:]]+|--yes[[:space:]]+)?skills(@[^[:space:]]*)?[[:space:]]+(add|install|i|update)'; then
        block "skills CLI install: $CMD"
    fi
    if echo "$CMD" | grep -qE '(claude[[:space:]]+mcp[[:space:]]+add|claude[[:space:]]+plugin[[:space:]]+install)'; then
        block "Claude Code install command: $CMD"
    fi
    if echo "$CMD" | grep -qE 'git[[:space:]]+clone.*\.claude/(skills|plugins|hooks|commands)'; then
        block "git clone into protected path: $CMD"
    fi
    local WRITE_VERB_RE='(>>?[[:space:]]|>$|tee[[:space:]]|touch[[:space:]]|cp[[:space:]]|mv[[:space:]]|rm[[:space:]]|sed[[:space:]]+-i|install[[:space:]]|ln[[:space:]]|rsync[[:space:]]|printf[[:space:]].*>)'
    if echo "$CMD" | grep -qE "$WRITE_VERB_RE"; then
        for path in "${PROTECTED_PATHS[@]}"; do
            if [[ "$CMD_EXPANDED" == *"$path"* ]]; then
                block "write/move/delete targeting protected path in: $CMD"
            fi
        done
        if [ "$PROTECT_CLAUDE_MD" != "0" ] && [[ "$CMD_EXPANDED" == *"CLAUDE.md"* ]]; then
            block "write/move/delete targeting CLAUDE.md in: $CMD"
        fi
    fi
}

# 5. Checks that do not need the target check
CMD=""
case "$TOOL_NAME" in
    Edit|Write|MultiEdit|NotebookEdit)
        FILE_PATH=$(field '.tool_input.file_path')
        [ -z "$FILE_PATH" ] && FILE_PATH=$(field '.tool_input.notebook_path')
        if [ -n "$FILE_PATH" ] && is_protected_path "$FILE_PATH"; then
            block "$TOOL_NAME on protected path: $FILE_PATH"
        fi
        ;;
    Bash)
        CMD=$(field '.tool_input.command')
        [ -z "$CMD" ] && exit 0
        # The sandbox override flag disables all sandbox protections (Claude Code issue #10089).
        if echo "$CMD" | grep -q "dangerouslyOverrideSandbox"; then
            block "dangerouslyOverrideSandbox detected: $CMD . This bypasses all sandbox protections."
        fi
        ;;
esac

# 6. Target check. Prints the reason and exits 3 to block, exits 0 to allow.
#    Any other exit means it could not run: the older rule decides.
IFS= read -r -d '' GUARD_PY <<'PY'
import glob, json, os, re, shlex, sys

HOME = os.environ.get("HOME", "")
inp = json.loads(os.environ["GUARD_INPUT"])
tool = inp.get("tool_name", "")
ti = inp.get("tool_input") or {}
start_cwd = inp.get("cwd") or os.getcwd()

C = os.path.join(HOME, ".claude")
# The protected list comes from the shell (config file or defaults), one path per line.
# A trailing slash, or an existing folder, means "this folder and everything in it".
PROT_DIRS, PROT_FILES = [], []
for raw in os.environ.get("GUARD_PROTECTED", "").split("\n"):
    raw = raw.strip()
    if not raw:
        continue
    if raw.endswith("/") or os.path.isdir(raw):
        PROT_DIRS.append(os.path.normpath(raw))
    else:
        PROT_FILES.append(os.path.normpath(raw))
PROTECT_RULES_FILE = os.environ.get("GUARD_PROTECT_CLAUDE_MD", "1") != "0"
PROT_DIRS_L = [p.lower() for p in PROT_DIRS]
PROT_FILES_L = [p.lower() for p in PROT_FILES]
LOOSE_NAMES = tuple(sorted({os.path.basename(p).lower() for p in PROT_DIRS + PROT_FILES if os.path.basename(p)}))


def block(reason):
    print(reason)
    sys.exit(3)


def variants(path):
    out = {os.path.normpath(path)}
    try:
        out.add(os.path.realpath(path))
    except Exception:
        pass
    return out


def hit_listed(path):
    """True when the path is a protected file or sits inside a protected folder."""
    for v in variants(path):
        low = v.lower()
        if low in PROT_FILES_L or low in PROT_DIRS_L:
            return True
        if any(low.startswith(d + "/") for d in PROT_DIRS_L):
            return True
    return False


def hit(path):
    """True when the path is a protected file, sits inside a protected folder, or is a CLAUDE.md."""
    if hit_listed(path):
        return True
    for v in variants(path):
        low = v.lower()
        if PROTECT_RULES_FILE and ("CLAUDE.md" in v or os.path.basename(low) == "claude.md"):
            return True
    return False


def bulk_risky(path):
    """True for a folder inside the home folder that contains protected paths (the config folder
    itself, for example). Used for commands that drop many files into a folder at once. The home
    folder itself does not count: unpacking an archive in the home folder is ordinary work."""
    home_low = os.path.normpath(HOME).lower()
    for v in variants(path):
        low = v.lower().rstrip("/")
        if low == home_low or not low.startswith(home_low + "/"):
            continue
        if any(q.startswith(low + "/") for q in PROT_DIRS_L + PROT_FILES_L):
            return True
    return False


def brace_expand(word, limit=64):
    """a/{b,c}/d becomes a/b/d and a/c/d, the way the shell does it."""
    m = re.search(r"\{([^{}]*,[^{}]*)\}", word)
    if not m:
        return [word]
    out = []
    for alt in m.group(1).split(","):
        out += brace_expand(word[:m.start()] + alt + word[m.end():], limit)
        if len(out) > limit:
            break
    return out


def bulk_only(path):
    """True when the path is the home folder itself, where only the bulk rule applies."""
    p = path
    if p == "~" or p.startswith("~/"):
        p = HOME + p[1:]
    return os.path.normpath(p).lower() == os.path.normpath(HOME).lower()


def holds_protected(path):
    """True when the path is a folder that contains protected paths (for example the config folder)."""
    for v in variants(path):
        low = v.lower().rstrip("/")
        if any(p.startswith(low + "/") for p in PROT_DIRS_L + PROT_FILES_L):
            return True
    return False


def expand_home(text):
    text = text.replace("${HOME}", HOME).replace("$HOME", HOME)
    return re.sub(r"(?<![\w/.~-])~(?=/|$|[\s'\"])", HOME, text)


def mentions(text):
    """Loose test: does this text name a protected place at all?"""
    low = expand_home(text).lower()
    if any(p in low for p in PROT_DIRS_L + PROT_FILES_L):
        return True
    if PROTECT_RULES_FILE and "CLAUDE.md" in text:
        return True
    if ".agents" in low and "skills" in low:
        return True
    return ".claude" in low and any(n in low for n in LOOSE_NAMES)


WRITEISH = re.compile(
    r"open\s*\([^)]*,\s*['\"][wax+]|\.write|write_text|write_bytes|writeFile|appendFile|unlink|"
    r"\bremove|rmtree|rename|\breplace\s*\(|shutil|os\.system|subprocess|chmod|truncate|mkdir|"
    r"makedirs|touch|symlink|\bcopy|\bmove|\bdump\s*\(|fs\.|>|\brm\b|\bmv\b|\bcp\b|\btee\b|"
    r"sed\s+-i|\bdelete\b|file_put_contents|fwrite|fputs|toFile")

PY_STRING = re.compile(r'''"""(.*?)"""|\'\'\'(.*?)\'\'\'|"((?:[^"\\\n]|\\.)*)"|\'((?:[^\'\\\n]|\\.)*)\'''', re.S)
PY_SHELL = re.compile(r"os\.system|subprocess|popen|pty\.|\bexec\s*\(|\beval\s*\(|os\.exec|os\.spawn")


def code_writes_protected(verb, code):
    """Does code fed to an interpreter name a protected place and write?
    For python, text inside a string that has spaces is a sentence, not a path, and is ignored,
    unless the code starts shell commands (then every mention counts)."""
    if not WRITEISH.search(code):
        return False
    if re.match(r"^python[\d.]*$", verb) and not PY_SHELL.search(code):
        def blank(m):
            lit = next((g for g in m.groups() if g is not None), "")
            looks_like_path = re.match(r"^(/|~|\$HOME|\$\{HOME\}|\.{1,2}/|\.claude|\.agents)", lit) and \
                re.search(r"\.claude|\.agents|CLAUDE\.md|\.god-mode-os", lit)  # a path with a space in it, not a sentence
            return m.group(0) if (looks_like_path or not re.search(r"\s", lit)) else '""'
        return mentions(PY_STRING.sub(blank, code))
    return mentions(code)


DATA_VERBS = {"cat", "tee"}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
INTERPRETERS = {"python", "python3", "node", "perl", "ruby", "osascript", "php", "deno", "bun", "swift"}
# GNU-prefixed names on macOS behave like their plain names.
VERB_ALIAS = {"gsed": "sed", "gcp": "cp", "gmv": "mv", "grm": "rm", "gln": "ln", "ginstall": "install",
              "gtar": "tar", "gtouch": "touch", "gmkdir": "mkdir", "gchmod": "chmod", "gchown": "chown",
              "gdd": "dd", "gtee": "tee", "gtruncate": "truncate", "gshred": "shred", "gfind": "find"}
# Wrappers that run another command. Value: their own options that take a value.
WRAPPERS = {"timeout": ("-s", "-k", "--signal", "--kill-after"), "gtimeout": ("-s", "-k", "--signal", "--kill-after"),
            "sudo": ("-u", "-g", "-h", "-p", "-C", "-D", "-R", "-T", "-U"), "doas": ("-u", "-C"),
            "nice": ("-n",), "ionice": ("-c", "-n", "-p"), "stdbuf": (), "caffeinate": ("-t", "-w"),
            "arch": (), "nohup": (), "time": ()}
# Commands that only read their arguments. Any other command that is pointed straight at a
# protected path is blocked, because the guard cannot know what it does there.
READERS = {"gitleaks", "mcp-scan", "sha512sum", "b3sum", "gstat", "colordiff",
           "icdiff", "ack", "ugrep", "expand", "fold", "paste", "iconv",
           "cat", "ls", "ll", "grep", "egrep", "fgrep", "rg", "ag", "head", "tail", "wc", "jq", "yq", "diff",
           "cmp", "comm", "stat", "file", "less", "more", "bat", "open", "shasum", "sha1sum", "sha256sum",
           "md5", "md5sum", "cksum", "sort", "uniq", "cut", "awk", "gawk", "tr", "basename", "dirname",
           "realpath", "readlink", "du", "df", "tree", "test", "[", "[[", "echo", "printf", "for", "select",
           "case", "in", "function", "export", "local", "declare", "typeset", "readonly", "read", "source",
           ".", "set", "unset", "return", "exit", "true", "false", "wait", "sleep", "type", "which",
           "whereis", "hash", "nl", "tac", "rev", "column", "xxd", "od", "hexdump", "strings", "base64",
           "zcat", "gzcat", "bzcat", "xzcat", "zgrep", "date", "mdls", "mdfind", "id", "env", "printenv",
           "shellcheck", "code", "done", "fi", "esac", "gh", "zip", "pbcopy", "plutil", "eza", "exa",
           "lsd", "gls", "fd", "fdfind", "cloc", "tokei", "glow", "mdcat", "delta", "difft", "ccat"}
# Flags that make one of the readers above write. With such a flag the command is no longer a reader.
READER_WRITE_FLAGS = {
    "yq": r"^(-i|--inplace|-[a-zA-Z]*i[a-zA-Z]*)$", "awk": r"^(-i|--include=inplace)$", "gawk": r"^(-i|--include=inplace)$",
    "sort": r"^(-o|--output(=.*)?|-[a-zA-Z]*o)$", "zip": r"^-[a-zA-Z]*m[a-zA-Z]*$", "xxd": r"^-[a-zA-Z]*r[a-zA-Z]*$",
    "base64": r"^(-o|--output(=.*)?)$", "plutil": r"^-(replace|insert|remove|convert|extract|create)$",
    "jq": r"^$", "open": r"^$", "code": r"^$",
    "gitleaks": r"^(-r|--report-path(=.*)?|--log-opts(=.*)?)$", "iconv": r"^(-o|--output(=.*)?)$",
}
# Scanners that may be started through a package runner (npx, uvx ...) and still count as readers.
# The name must be given bare: no path, no version, no runner option.
RUNNER_SAFE = {"mcp-scan", "gitleaks"}
# Tools whose first words are sub-commands, not file names (npm test, docker ps, brew list ...).
SUBCOMMAND_TOOLS = {"npm", "pnpm", "yarn", "bun", "docker", "brew", "ollama", "pip", "pip3", "launchctl", "vercel",
                    "supabase", "cargo", "go", "kubectl", "gh", "git", "ps", "kill", "say", "netlify", "wrangler"}
# Flags that mean "write the result back into the file", used for tools the guard does not know.
REWRITE_FLAGS = ("--write", "-w", "-i", "--in-place", "--inplace", "--fix", "--overwrite", "-rm")
# Wrappers of the form "<tool> run <command>".
RUN_WRAPPERS = {"uv": ("--with", "--python", "-p", "--project", "--directory"), "poetry": ("-C", "--directory", "-P", "--project"),
                "pipenv": (), "pdm": ("-p", "--project"), "hatch": (), "conda": ("-n", "--name", "-p", "--prefix"),
                "mamba": ("-n", "--name", "-p", "--prefix"), "rye": ()}
ALL_ARGS = {"rm", "rmdir", "unlink", "touch", "mkdir", "chmod", "chown", "chgrp", "chflags",
            "truncate", "shred", "tee", "xattr", "trash", "patch", "sponge", "ed", "ex", "vi", "vim", "nano"}
ANCESTOR_TOO = {"rm", "rmdir", "unlink", "trash", "rsync", "ditto"}
RECURSIVE_ONLY = {"chmod", "chown", "chgrp", "chflags", "xattr"}
LAST_ARG = {"cp", "install", "ln", "rsync", "scp", "ditto", "mv"}
GIT_CHANGE = {"checkout", "restore", "reset", "clean", "stash", "pull", "merge", "rebase", "apply",
              "am", "rm", "mv", "revert", "cherry-pick", "switch", "worktree", "submodule"}
WRITE_VERBS = ALL_ARGS | LAST_ARG | RECURSIVE_ONLY | {"sed", "dd", "curl", "wget", "tar", "unzip", "perl"}
PREFIX = {"sudo", "command", "env", "time", "nohup", "exec", "builtin", "then", "do", "else",
          "elif", "if", "while", "until", "!", "{", "}"}
GIT_READ = {"status", "log", "diff", "show", "ls-files", "rev-parse", "describe", "blame",
            "branch", "remote", "config", "grep", "cat-file", "shortlog", "ls-remote", "commit",
            "add", "fetch", "push", "tag"}
TOGGLE_OFF = {"off", "disable"}


def heredoc_strip(cmd, cwd, depth):
    """Remove heredoc bodies. A body fed to cat or tee is data and is ignored.
    A body fed to a shell is checked as a command. Any other body is checked as code."""
    lines = cmd.split("\n")
    out = []
    i = 0
    opener = re.compile(r"(?<!<)<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
    while i < len(lines):
        line = lines[i]
        found = list(opener.finditer(line))
        out.append(line)
        i += 1
        for m in found:
            before = line[:m.start()]
            if before.count('"') % 2 or before.count("'") % 2:
                continue
            word = m.group(2)
            seg = re.split(r"\|\||&&|;|\||\(", line[:m.start()])[-1].strip()
            words = [w for w in seg.split() if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w)]
            verb = os.path.basename(words[0]) if words else ""
            body = []
            while i < len(lines) and lines[i].strip() != word:
                body.append(lines[i])
                i += 1
            closed = i < len(lines)
            i += 1
            text = "\n".join(body)
            if not closed:
                analyze(text, cwd, depth + 1)
                continue
            if not m.group(1) and ("$(" in text or "`" in text) and legacy(text):
                block("heredoc body runs a command that writes near a protected path: " + cmd)
            if verb in DATA_VERBS:
                continue
            if verb in SHELLS:
                analyze(text, cwd, depth + 1)
            elif code_writes_protected(verb, text):
                block("code fed to %s names a protected path and writes: %s" % (verb or "a command", cmd))
    return "\n".join(out)


def split_subst(text):
    """Pull the commands inside $( ) and backticks out of the text.
    Returns the text with a placeholder in their place, and the list of inner commands."""
    out, inners, i, n = [], [], 0, len(text)
    while i < n:
        ch = text[i]
        if ch == "\\" and i + 1 < n:
            out.append(text[i:i + 2])
            i += 2
            continue
        if ch == "$" and i + 1 < n and text[i + 1] == "(":
            depth_, j = 1, i + 2
            while j < n and depth_:
                if text[j] == "(":
                    depth_ += 1
                elif text[j] == ")":
                    depth_ -= 1
                j += 1
            inners.append(text[i + 2:j - 1] if depth_ == 0 else text[i + 2:])
            out.append("$__SUBST")
            i = j
            continue
        if ch == "`":
            j = text.find("`", i + 1)
            if j == -1:
                j = n
            inners.append(text[i + 1:j])
            out.append("$__SUBST")
            i = j + 1
            continue
        out.append(ch)
        i += 1
    return "".join(out), inners


def legacy(cmd):
    """The old rule: any write verb plus any mention of a protected place."""
    verb_re = (r"(>>?\s|>$|tee\s|touch\s|cp\s|mv\s|rm\s|sed\s+-i|install\s|ln\s|rsync\s|"
               r"printf\s.*>|chmod\s|mkdir\s|-delete|curl\s|wget\s)")
    return bool(re.search(verb_re, cmd, re.M)) and mentions(cmd)


def analyze(cmd, cwd, depth=0):
    if depth > 4:
        if legacy(cmd):
            block("write/move/delete targeting protected path in: " + cmd)
        return
    cmd = cmd.replace("\\\n", " ")
    stripped = heredoc_strip(cmd, cwd, depth)
    stripped, inner_cmds = split_subst(stripped)
    for inner in inner_cmds:
        analyze(inner, cwd, depth + 1)
    try:
        lex = shlex.shlex(stripped, posix=True, punctuation_chars=";&|()<>\n")
        lex.whitespace = " \t\r"
        lex.whitespace_split = True
        lex.commenters = ""
        tokens = list(lex)
    except ValueError:
        if legacy(cmd):
            block("write/move/delete targeting protected path in: " + cmd)
        return

    variables = {"HOME": HOME}
    state = {"cwd": cwd, "cwd_known": True}

    def subst(word):
        def rep(m):
            name = m.group(1) or m.group(2)
            return variables.get(name, m.group(0))
        return re.sub(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)", rep, word)

    def resolve(word):
        """Returns (absolute path or None, is_dynamic)."""
        w = subst(word)
        if "$" in w or "`" in w:
            return None, True
        if w == "~" or w.startswith("~/"):
            w = HOME + w[1:]
        if not os.path.isabs(w):
            if not state["cwd_known"]:
                return None, True
            w = os.path.join(state["cwd"], w)
        return w, False

    def check_target(word, verb, ancestor=False, bulk=False):
        alts = brace_expand(word)
        if len(alts) > 1:
            for alt in alts:
                check_target(alt, verb, ancestor, bulk)
            return
        path, dyn = resolve(word)
        if dyn:
            # judge by the fixed front part of the word where that settles it
            w = subst(word)
            front = re.split(r"[$`]", w, maxsplit=1)[0]
            if front == "~" or front.startswith("~/"):
                front = HOME + front[1:]
            if os.path.isabs(front):
                low = os.path.normpath(front).lower() + ("/" if front.endswith("/") else "")
                if front.endswith("/"):
                    risky = hit(front) or holds_protected(front)
                else:
                    risky = (hit(os.path.dirname(front)) or hit(front)
                             or any(q.startswith(low) for q in PROT_DIRS_L + PROT_FILES_L))
                if risky:
                    block("write/move/delete with a variable part under a protected path (%s -> %s) in: %s" % (verb, w, cmd))
                return
            if mentions(stripped) or any(mentions(c) for c in inner_cmds) or hit(state["cwd"]) or (not state["cwd_known"] and mentions(cmd)):
                block("cannot tell where '%s' writes and the command names a protected path: %s" % (verb, cmd))
            return
        candidates = [path]
        if any(ch in path for ch in "*?["):
            candidates += glob.glob(path)
        for c in candidates:
            if hit(c) or (ancestor and holds_protected(c)) or (bulk and bulk_risky(c)):
                block("write/move/delete targeting protected path (%s -> %s) in: %s" % (verb, c, cmd))

    def run_simple(words, redirects):
        for r in redirects:
            check_target(r, "redirect")
        # leading assignments and prefix words
        while words:
            w = words[0]
            m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", w)
            if m:
                val = m.group(2)
                if val == "~" or val.startswith("~/"):
                    val = HOME + val[1:]
                variables[m.group(1)] = subst(val)
                words = words[1:]
            elif os.path.basename(w) in WRAPPERS:
                takes_value = WRAPPERS[os.path.basename(w)]
                i = 1
                while i < len(words) and words[i].startswith("-"):
                    i += 2 if words[i] in takes_value else 1
                if os.path.basename(w) in ("timeout", "gtimeout"):
                    i += 1  # the duration
                words = words[i:]
            elif w in RUN_WRAPPERS and words[1:2] == ["run"]:
                takes_value = RUN_WRAPPERS[w]
                i = 2
                while i < len(words) and words[i].startswith("-"):
                    i += 2 if words[i] in takes_value else 1
                words = words[i:]
            elif w in PREFIX:
                words = words[1:]
            else:
                break
        if not words:
            return
        verb = os.path.basename(words[0])
        verb = VERB_ALIAS.get(verb, verb)
        args = [x for a in words[1:] for x in brace_expand(a)]
        plain = [a for a in args if not a.startswith("-")]

        if verb == "popd":
            state["cwd_known"] = False
            return

        if verb in ("cd", "pushd"):
            if plain:
                path, dyn = resolve(plain[0])
                if dyn or plain[0] == "-":
                    state["cwd_known"] = False
                else:
                    state["cwd"] = path
            elif not args:
                state["cwd"] = HOME
            else:
                state["cwd_known"] = False
            return

        if verb == "claude":
            if ("mcp" in args and "add" in args) or ("plugin" in args and "install" in args):
                block("Claude Code install command: " + cmd)
            return

        # a skills CLI installs straight into the skills folders
        if verb in ("npx", "bunx", "pnpx") or (verb in ("pnpm", "npm", "yarn") and args[:1] in (["dlx"], ["exec"])):
            low = [x.lower() for x in args]
            if any(x == "skills" or x.startswith("skills@") for x in low) and any(x in ("add", "install", "i", "update") for x in low):
                block("skills CLI install (review the source first): " + cmd)

        # the guard switch itself: the user turns the guards off, not the agent
        names = [verb] + [os.path.basename(a) for a in plain]
        if "discipline-toggle.sh" in names and any(a in TOGGLE_OFF for a in args):
            block("switching the guards off is the user's step, not the agent's: " + cmd)

        if verb in SHELLS or verb == "eval":
            if verb == "eval":
                analyze(" ".join(args), state["cwd"], depth + 1)
            elif "-c" in args and args.index("-c") + 1 < len(args):
                analyze(args[args.index("-c") + 1], state["cwd"], depth + 1)
            else:
                for a in args:
                    if a.startswith("-") and not a.startswith("--") and "c" in a and args.index(a) + 1 < len(args):
                        analyze(args[args.index(a) + 1], state["cwd"], depth + 1)
                        break
            return

        if verb in INTERPRETERS or re.match(r"^python3?\.\d+$", verb):
            for k, a in enumerate(args):
                if a in ("-c", "-e", "-r", "--eval", "-pe", "-ne", "-pi", "-i") or (verb == "perl" and re.match(r"^-[a-zA-Z]*[ei]", a)):
                    code = " ".join(args[k:])
                    if code_writes_protected(verb, code):
                        block("inline %s code names a protected path and writes: %s" % (verb, cmd))
                    if verb == "perl" and re.match(r"^-[a-zA-Z]*i", a):
                        for p in plain:
                            check_target(p, "perl -i")
                    break
            return

        if verb in ("xargs", "parallel") or (verb == "find" and any(a in ("-exec", "-execdir", "-ok", "-okdir") for a in args)):
            inner = [os.path.basename(a) for a in args]
            if any(a in WRITE_VERBS or a in SHELLS for a in inner) or "-delete" in args:
                if mentions(stripped) or hit(state["cwd"]) or holds_protected(state["cwd"]):
                    block("write/move/delete through %s near a protected path in: %s" % (verb, cmd))
            if verb != "find":
                return

        if verb == "find":
            exec_writes = any(a in ("-exec", "-execdir", "-ok", "-okdir") for a in args) and \
                any(os.path.basename(a) in WRITE_VERBS or os.path.basename(a) in SHELLS for a in args)
            if exec_writes or any(a == "-delete" or a.startswith("-fprint") for a in args):
                roots = []
                rest = list(args)
                # leading global options come before the start folders; -f names a start folder itself
                while rest and (re.match(r"^-[HLPEXdsxf]+$", rest[0]) or rest[0] in ("-D", "--") or re.match(r"^-O\d*$", rest[0])):
                    if rest[0] == "-D" and len(rest) > 1:
                        rest = rest[2:]
                    elif not rest[0].startswith("-O") and "f" in rest[0] and len(rest) > 1:
                        roots.append(rest[1])
                        rest = rest[2:]
                    else:
                        rest = rest[1:]
                for a in rest:
                    if a.startswith("-") or a in ("(", "!"):
                        break
                    roots.append(a)
                for r in roots or ["."]:
                    check_target(r, "find -delete", ancestor=True)
            return

        if verb == "xattr" and not any(re.match(r"^-[a-zA-Z]*[wdc]", a) for a in args):
            return

        if verb == "patch":
            where = state["cwd"]
            for k, a in enumerate(args):
                if a in ("-d", "--directory") and k + 1 < len(args):
                    where, _dyn = resolve(args[k + 1])
                    where = where or state["cwd"]
                elif a.startswith("--directory="):
                    where, _dyn = resolve(a.split("=", 1)[1])
                    where = where or state["cwd"]
            if hit(os.path.join(where, "x")) or hit(where) or bulk_risky(where):
                block("patch applied inside a protected folder (%s) in: %s" % (where, cmd))

        if verb == "gh":
            if args[:2] == ["repo", "clone"]:
                if len(plain) >= 4:
                    check_target(plain[3], "gh repo clone", ancestor=True)
                elif len(plain) == 3:
                    check_target(os.path.basename(plain[2]), "gh repo clone")
            return

        if verb in ALL_ARGS or verb in RECURSIVE_ONLY:
            deep = verb in ANCESTOR_TOO or (verb in RECURSIVE_ONLY and any(re.match(r"^-[a-zA-Z]*[Rr]", a) for a in args))
            for p in plain:
                check_target(p, verb, ancestor=deep)
            return

        if verb in LAST_ARG:
            if not plain:
                return
            # a link (symbolic or hard) to a protected place lets a later command write through another name
            makes_link = verb == "ln" or (verb == "cp" and any(
                re.match(r"^-[a-zA-Z]*[sl]", a) or a.startswith("--l") or a.startswith("--sy") for a in args))
            # The target-folder option (cp, mv, ln, install only; for rsync -t means "keep times").
            # Read the options the way the tool does: a bundle stops at the first letter that takes a
            # value, and a long option may be shortened to any prefix. Once the target folder is known,
            # it becomes the destination and the ordinary checks below run on it.
            takes_value = {"cp": "S", "mv": "S", "ln": "S", "install": "Sgom"}.get(verb)
            if takes_value is not None:
                t_seen, t_val, sources, k = False, None, [], 0
                while k < len(args):
                    a = args[k]
                    if a == "--":
                        sources += args[k + 1:]
                        break
                    if a.startswith("--"):
                        name = a.split("=", 1)[0]
                        if len(name) >= 3 and "--target-directory".startswith(name):
                            t_seen = True
                            if "=" in a:
                                t_val = a.split("=", 1)[1]
                            elif k + 1 < len(args):
                                t_val = args[k + 1]
                                k += 1
                    elif a.startswith("-") and len(a) > 1:
                        for pos in range(1, len(a)):
                            ch = a[pos]
                            if ch == "t":
                                t_seen = True
                                if a[pos + 1:]:
                                    t_val = a[pos + 1:]
                                elif k + 1 < len(args):
                                    t_val = args[k + 1]
                                    k += 1
                                break
                            if ch in takes_value:
                                if not a[pos + 1:]:
                                    k += 1  # its value is the next word
                                break
                    else:
                        sources.append(a)
                    k += 1
                if t_seen and t_val is None:
                    for p in plain:
                        check_target(p, verb, ancestor=True)
                    return
                # Tools disagree on an option that comes after the first file: GNU still reads it as an
                # option, the macOS tools and strict mode read it and what follows as files. When that
                # happens the guard cannot know which word is the destination, so every word is checked.
                first_file = next((k for k, a in enumerate(args) if not a.startswith("-")), None)
                late = [k for k, a in enumerate(args) if first_file is not None and k > first_file
                        and a.startswith("-") and len(a) > 1]
                if late and any(not a.startswith("-") for a in args[late[0] + 1:]):
                    for p in plain:
                        check_target(p, verb)
                if t_seen:
                    check_target(os.path.join(t_val, "x"), verb)
                    plain = sources + [t_val]
                else:
                    plain = sources  # without the values that belong to options
                if not plain:
                    return
            dest = plain[-1]
            if makes_link:
                for src in plain[:-1]:
                    check_target(src, verb, ancestor=True)
            if verb == "mv" or "--remove-source-files" in args:
                for src in plain[:-1]:
                    check_target(src, verb, ancestor=True)
            check_target(dest, verb, bulk=verb in ANCESTOR_TOO)
            dpath, dyn = resolve(dest)
            if not dyn and bulk_risky(dpath) and any(
                    any(ch in src for ch in "*?[$") or src == "." or src.endswith("/.") or src.endswith("/")
                    for src in plain[:-1]):
                block("many files copied over a folder that holds protected paths (%s -> %s) in: %s" % (verb, dpath, cmd))
            if not dyn and (dest.endswith("/") or os.path.isdir(dpath)):
                for src in plain[:-1]:
                    base = os.path.basename(subst(src).rstrip("/"))
                    if base and not any(ch in base for ch in "*?[$"):
                        check_target(os.path.join(dpath, base), verb, bulk=True)
            return

        if verb == "sed":
            # Which words are scripts is decided the way sed decides it: every -e / --expression value,
            # or, when there is none and no script file, the first plain word. File names are not scripts.
            scripts, plain_words, explicit, k = [], [], False, 0
            while k < len(args):
                a = args[k]
                if a.startswith("--"):
                    name = a.split("=", 1)[0]
                    if len(name) >= 3 and "--expression".startswith(name):
                        explicit = True
                        if "=" in a:
                            scripts.append(a.split("=", 1)[1])
                        elif k + 1 < len(args):
                            scripts.append(args[k + 1])
                            k += 1
                    elif len(name) >= 3 and "--file".startswith(name):
                        explicit = True
                elif a.startswith("-") and len(a) > 1:
                    for pos in range(1, len(a)):
                        ch = a[pos]
                        if ch == "e":
                            explicit = True
                            if a[pos + 1:]:
                                scripts.append(a[pos + 1:])
                            elif k + 1 < len(args):
                                scripts.append(args[k + 1])
                                k += 1
                            break
                        if ch == "f":
                            explicit = True
                            if not a[pos + 1:]:
                                k += 1
                            break
                        if ch in "il":
                            break  # may carry a glued value
                else:
                    plain_words.append(a)
                k += 1
            # Some options take the next word as their value (-i and -I on macOS, -l, --line-length),
            # and the tools disagree on which. With one of them present every plain word is looked
            # at as a possible script, whether or not a script was also given with -e.
            value_opt = any(re.match(r"^-[a-zA-Z]*[iIl]$", a) or re.match(r"^--l[a-z-]*$", a) for a in args)
            if value_opt:
                scripts += plain_words
            elif not explicit:
                scripts += plain_words[:1]

            def subst_flags(script):
                """The flags of every s command in a sed script. Any delimiter, backslashes honored."""
                found, pos = [], 0
                while pos < len(script) - 1:
                    d = script[pos + 1]
                    if script[pos] == "s" and d not in "\\\n" and not d.isspace():
                        prev = script[pos - 1] if pos else ""
                        strict = (not prev) or prev in ";{}\n!$,/IM" or prev.isdigit() or prev.isspace()
                        if strict or not d.isalnum():
                            q, fields = pos + 2, 0
                            while q < len(script) and fields < 2:
                                if script[q] == "\\":
                                    q += 2
                                    continue
                                if script[q] == d:
                                    fields += 1
                                q += 1
                            if fields == 2:
                                m = re.match(r"[a-zA-Z0-9]*", script[q:])
                                found.append(m.group(0))
                                pos = q + len(m.group(0))
                                continue
                    pos += 1
                return found

            for a in scripts:
                writes = re.search(r"(^|[;{}\s/])[wW]\s+\S", a)
                runs = re.search(r"(^|[;{}\s\d$])e(\s|$)", a) or any("e" in f for f in subst_flags(a))
                if re.search(r"(^|[;{}\n\s,!])\\[^/\n]", a):
                    runs = True  # an address with a delimiter of its own: the guard does not read past it
                if writes and (mentions(a) or ("$" in a and mentions(cmd))):
                    block("sed script writes to a protected path in: %s" % cmd)
                if runs and mentions(cmd):
                    block("sed script runs a command and the command line names a protected path: %s" % cmd)
            def long_is(a, full):
                name = a.split("=", 1)[0]
                return a.startswith("--") and len(name) >= 3 and full.startswith(name)

            if any(long_is(a, "--file") or (not a.startswith("--") and re.match(r"^-[a-zA-Z]*f", a)) for a in args) and mentions(cmd):
                block("sed runs a script file the guard cannot read, and the command line names a protected path: %s" % cmd)
            if any((not a.startswith("--") and re.match(r"^-[a-zA-Z]*[iI]", a)) or long_is(a, "--in-place") for a in args):
                for p in plain:
                    check_target(p, "sed -i")
            return

        if verb == "dd":
            for a in args:
                if a.startswith("of="):
                    check_target(a[3:], "dd")
            return

        if verb in ("curl", "wget"):
            out_dir = None
            for k, a in enumerate(args):
                if a == "--output-dir" and k + 1 < len(args):
                    out_dir = args[k + 1]
                elif a.startswith("--output-dir="):
                    out_dir = a.split("=", 1)[1]
            if out_dir:
                check_target(out_dir, verb, ancestor=True)
            named_output = False
            for k, a in enumerate(args):
                nxt = args[k + 1] if k + 1 < len(args) else None
                if verb == "curl":
                    if (a in ("--output",) or re.match(r"^-[A-Za-z]*o$", a)) and nxt:
                        check_target(os.path.join(out_dir, nxt) if out_dir and not os.path.isabs(nxt) else nxt, verb)
                    elif a.startswith("--output="):
                        check_target(a.split("=", 1)[1], verb)
                    elif re.match(r"^-o.+", a):
                        check_target(a[2:], verb)
                    elif a in ("--remote-name", "--remote-name-all") or re.match(r"^-[A-Za-z]*O$", a):
                        check_target(os.path.join(out_dir, "downloaded-file") if out_dir else "downloaded-file", verb)
                else:
                    if (a == "--output-document" or re.match(r"^-[A-Za-z]*O$", a)) and nxt:
                        named_output = True
                        check_target(nxt, verb)
                    elif a.startswith("--output-document="):
                        named_output = True
                        check_target(a.split("=", 1)[1], verb)
                    elif (a == "--directory-prefix" or re.match(r"^-[A-Za-z]*P$", a)) and nxt:
                        named_output = True
                        check_target(nxt, verb, ancestor=True)
                    elif a.startswith("--directory-prefix="):
                        named_output = True
                        check_target(a.split("=", 1)[1], verb, ancestor=True)
            if verb == "wget" and not named_output:
                check_target("downloaded-file", verb)
            return

        if verb in ("tar", "unzip", "bsdtar"):
            dest = None
            for k, a in enumerate(args):
                if (a in ("-C", "-d", "--directory") or re.match(r"^-[a-zA-Z]*C$", a)) and k + 1 < len(args):
                    dest = args[k + 1]
                elif a.startswith("--directory="):
                    dest = a.split("=", 1)[1]
            extracting = (verb == "unzip"
                          or any(re.match(r"^-[a-zA-Z]*x", a) or a in ("--extract", "--get") for a in args)
                          or bool(args and not args[0].startswith("-") and re.match(r"^[a-zA-Z]*x[a-zA-Z]*$", args[0])))
            if verb == "unzip" and any(a in ("-l", "-t", "-Z", "-v") for a in args):
                extracting = False
            if extracting:
                where = dest if dest else "."
                check_target(os.path.join(where, "extracted-file"), verb)
                check_target(where, verb, ancestor=bool(dest) and not bulk_only(where), bulk=True)
            else:
                for k, a in enumerate(args):
                    if re.match(r"^-?[a-zA-Z]*f$", a) and k + 1 < len(args):
                        check_target(args[k + 1], verb)
            return

        if verb == "git":
            where = state["cwd"]
            rest = list(args)
            while rest and rest[0].startswith("-"):
                if rest[0] == "-C" and len(rest) > 1:
                    p, dyn = resolve(rest[1])
                    where = p if not dyn else where
                    if dyn and mentions(stripped):
                        block("git in a folder that cannot be told, and the command names a protected path: " + cmd)
                    rest = rest[2:]
                elif rest[0] in ("-c",) and len(rest) > 1:
                    rest = rest[2:]
                else:
                    rest = rest[1:]
            if not rest:
                return
            sub = rest[0]
            sub_plain = [a for a in rest[1:] if not a.startswith("-")]
            if sub == "clone":
                if len(sub_plain) >= 2:
                    check_target(sub_plain[-1], "git clone", ancestor=True)
                else:
                    check_target("cloned-repo", "git clone")
            elif sub not in GIT_READ and (hit(os.path.join(where, "x")) or hit(where)):
                block("git %s inside a protected folder (%s) in: %s" % (sub, where, cmd))
            elif sub in GIT_CHANGE and holds_protected(where):
                block("git %s can rewrite protected files under %s in: %s" % (sub, where, cmd))
            return
        # Known readers (ls, cat, grep, head, wc, jq, diff, stat ...) only read, unless they carry
        # one of their own write flags. Any other command that is pointed straight at a protected
        # path is blocked: the guard cannot know what it does there. A project rules file is the
        # exception: unknown tools may read it (lint, convert, check), and are blocked only when
        # they carry a flag that writes the result back.
        if "=" in verb:
            return
        reader = verb in READERS
        if verb in ("npx", "uvx", "bunx", "pnpx"):
            # a tool started through a runner is judged as that tool
            inner = args[0] if args else ""
            if inner in RUNNER_SAFE and not (inner in READER_WRITE_FLAGS and any(
                    re.match(READER_WRITE_FLAGS[inner], a) for a in args if a.startswith("-"))):
                return
        if verb in ("awk", "gawk", "mawk", "nawk"):
            # an awk program can redirect, pipe or run a shell command by itself
            v_values = [args[k + 1] for k, a in enumerate(args[:-1]) if a in ("-v", "--assign")]
            # short options can be bundled (-bvf=x): walk each bundle up to the first letter that takes a value
            loads_code = False
            for k, a in enumerate(args):
                if not a.startswith("-") or a.startswith("--") or len(a) < 2:
                    continue
                for pos in range(1, len(a)):
                    ch = a[pos]
                    if ch in "opd":
                        # gawk writes a pretty-print, a profile or a variable dump to the glued file name
                        # with nothing glued gawk uses a default name in the current folder
                        check_target(a[pos + 1:] or ("awkvars.out" if ch == "d" else "awkprof.out"), "awk")
                        break
                    if ch in "vfEilWF":
                        value = a[pos + 1:] or (args[k + 1] if k + 1 < len(args) else "")
                        if ch == "v":
                            v_values.append(value)
                        elif ch != "F":
                            loads_code = True
                        break
            # long options may be shortened to any unique prefix, so every --name=value counts,
            # and so does the word after a bare --as... option
            v_values += [a.split("=", 1)[1] for a in args if a.startswith("--") and "=" in a]
            v_values += [args[k + 1] for k, a in enumerate(args[:-1]) if re.match(r"^--as[a-z]*$", a)]
            v_values += [a for a in args if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", a)]
            for a in args:
                writeish = re.search(r"\bprintf?\b[^;}\n]*>|\||system\(", a)
                if not writeish and ">" in a and mentions(a):
                    writeish = True  # a redirect the pattern could not place, next to a protected path
                if not writeish:
                    continue
                if mentions(a) or any(mentions(v) for v in v_values) \
                        or (re.search(r"ARGV|ENVIRON", a) and mentions(cmd)):
                    block("awk program writes to or runs a command on a protected path in: %s" % cmd)
            for a in args:
                m = re.match(r"^--(pr|d)[a-z-]*(?:=(.+))?$", a)  # --pretty-print, --profile, --dump-variables
                if m:
                    check_target(m.group(2) or ("awkvars.out" if m.group(1) == "d" else "awkprof.out"), "awk")
            # script files, includes and extensions are code the guard cannot read
            if (loads_code or any(re.match(r"^--(f|e|i|l)[a-z]*(=|$)", a) for a in args)) and mentions(cmd):
                block("awk loads a script, include or extension the guard cannot read, and the command line names a protected path: %s" % cmd)
        if verb == "zip":
            takes_value = ("-b", "--temp-path", "-n", "--suffixes", "-t", "--from-date", "-tt", "--before-date",
                           "-x", "--exclude", "-i", "--include", "-TT", "--unzip-command", "-O", "--output-file", "--out")
            archive, k = None, 0
            while k < len(args):
                a = args[k]
                if a in ("-O", "--output-file", "--out") and k + 1 < len(args):
                    check_target(args[k + 1], "zip")
                if a in ("-TT", "--unzip-command") and mentions(cmd):
                    block("zip runs a test command and the command line names a protected path: %s" % cmd)
                if a in ("-x", "--exclude", "-i", "--include"):
                    k += 1  # a list of patterns follows, up to the next option
                    while k < len(args) and not args[k].startswith("-"):
                        k += 1
                    continue
                if a in takes_value:
                    k += 2
                    continue
                if not a.startswith("-") and archive is None:
                    archive = a
                k += 1
            if archive:
                check_target(archive, "zip")
        if reader and verb in READER_WRITE_FLAGS and any(re.match(READER_WRITE_FLAGS[verb], a) for a in args if a.startswith("-")):
            reader = False
        if reader:
            return
        rewrites = any(a in REWRITE_FLAGS for a in args)
        candidates = list(plain)
        for a in args:  # --flag=path
            if a.startswith("-") and "=" in a:
                candidates.append(a.split("=", 1)[1])
        for p in candidates:
            path, dyn = resolve(p)
            if dyn or not path:
                continue
            if verb in SUBCOMMAND_TOOLS and not ("/" in p or "." in p or p.startswith("~") or os.path.lexists(path)):
                continue  # a sub-command word such as "test" or "list", not a file
            if hit_listed(path) or (rewrites and hit(path)):
                block("'%s' is not a known read-only command and is pointed at a protected path (%s) in: %s" % (verb, path, cmd))

    words, redirects = [], []
    k = 0
    n = len(tokens)
    while k < n:
        t = tokens[k]
        if t and all(ch in ";&|()<>\n" for ch in t):
            if ">" in t:
                nxt = tokens[k + 1] if k + 1 < n else ""
                if t.endswith("&") and (nxt.isdigit() or nxt == "-"):
                    k += 2
                    continue
                if nxt:
                    redirects.append(nxt)
                k += 2
                continue
            if "<" in t:
                k += 2
                continue
            run_simple(words, redirects)
            words, redirects = [], []
            k += 1
            continue
        words.append(t)
        k += 1
    run_simple(words, redirects)



if tool == "Bash":
    command = ti.get("command") or ""
    if command:
        analyze(command, start_cwd)
elif tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
    fp = ti.get("file_path") or ti.get("notebook_path") or ""
    if fp:
        if fp == "~" or fp.startswith("~/"):
            fp = HOME + fp[1:]
        if not os.path.isabs(fp):
            fp = os.path.join(start_cwd, fp)
        if hit(fp):
            block("%s on protected path: %s" % (tool, fp))
sys.exit(0)
PY
GUARD_PROTECTED_LIST=$(printf '%s\n' "${PROTECTED_PATHS[@]}")
REASON=$(GUARD_INPUT="$INPUT" GUARD_PROTECTED="$GUARD_PROTECTED_LIST" GUARD_PROTECT_CLAUDE_MD="$PROTECT_CLAUDE_MD" python3 -I -c "$GUARD_PY" 2>/dev/null)
RC=$?

if [ "$RC" -eq 3 ]; then
    block "${REASON:-write/move/delete targeting protected path}"
elif [ "$RC" -ne 0 ]; then
    log_event "gate-error" "\"target check failed (exit $RC), older rule used\""
    if [ "$TOOL_NAME" = "Bash" ]; then
        legacy_bash_check "$CMD"
    fi
fi

exit 0
