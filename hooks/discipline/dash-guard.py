#!/usr/bin/env python3
# dash-guard.py : PreToolUse hook on Write|Edit|MultiEdit|Bash. Opt-in.
# Stops em dashes, en dashes and spaced double hyphens before they reach a text file, and
# tells the agent the exact spot so it rewrites the sentence (a blind swap breaks grammar).
#
# Switch it on:   touch ~/.god-mode-os/dash-guard-on     (or set GMOS_DASH_GUARD=1)
#
# Scope: prose file types only (md, txt, html, eml, csv, rtf, tex). Ignored: fenced and inline
# code, URLs, quoted lines ("> "), HTML comments, and any line containing "dash-ok".
# Only the NEW text is checked (Edit new_string, never old_string). Fail-open on any error.
import json, os, re, sys, time

HOME = os.path.expanduser('~')
GMOS_HOME = os.environ.get('GMOS_HOME') or os.path.join(HOME, '.god-mode-os')
KILL_SWITCH = os.environ.get('GMOS_KILL_SWITCH') or os.path.join(HOME, '.claude', '.god-mode-disabled')
EXTS = ('.md', '.mdx', '.markdown', '.txt', '.html', '.htm', '.eml', '.csv', '.rtf', '.tex')
DASH = re.compile('[' + chr(8212) + chr(8211) + ']| -- ')
LOG = os.path.join(GMOS_HOME, 'dash-guard.log')


def prose(text):
    text = re.sub(r'```.*?```', ' ', text, flags=re.S)       # fenced code
    text = re.sub(r'<!--.*?-->', ' ', text, flags=re.S)       # HTML comments
    text = re.sub(r'`[^`\n]*`', ' ', text)                     # inline code
    text = re.sub(r'https?://\S+', ' ', text)                  # URLs
    keep = [l for l in text.split('\n') if not l.lstrip().startswith('>') and 'dash-ok' not in l]
    return '\n'.join(keep)


def offenders(text):
    p = prose(text)
    out = []
    for m in DASH.finditer(p):
        out.append(' '.join(p[max(0, m.start() - 35):m.end() + 35].split()))
        if len(out) == 3:
            break
    return out, len(DASH.findall(p))


def deny(path, snippets, total):
    try:  # count and file name only, never the text
        os.makedirs(GMOS_HOME, exist_ok=True)
        with open(LOG, 'a') as fh:
            fh.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} blocked {total} dash(es) in {os.path.basename(path)}\n")
    except Exception:
        pass
    shown = '\n'.join(f'  - "...{s}..."' for s in snippets)
    reason = (f"DASH GUARD: {total} em/en dash or spaced double hyphen in text for {path}. "
              f"Rewrite these sentences with a period, comma, colon or semicolon "
              f"(number ranges like 2019-2021 use a plain hyphen), then retry:\n{shown}\n"
              f"Quoting someone word for word? Put it on a '> ' quote line.")
    print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PreToolUse',
                                             'permissionDecision': 'deny',
                                             'permissionDecisionReason': reason}}))


def main():
    if os.path.exists(KILL_SWITCH) or os.environ.get('GMOS_ADMIN_OVERRIDE') == '1':
        return
    if os.environ.get('GMOS_DASH_GUARD') != '1' and not os.path.exists(os.path.join(GMOS_HOME, 'dash-guard-on')):
        return
    data = json.load(sys.stdin)
    tool = data.get('tool_name', '')
    ti = data.get('tool_input', {}) or {}
    if tool in ('Write', 'Edit', 'MultiEdit'):
        path = ti.get('file_path', '') or ''
        if not path.lower().endswith(EXTS):
            return
        if tool == 'Write':
            new = ti.get('content', '') or ''
        elif tool == 'Edit':
            new = ti.get('new_string', '') or ''
        else:
            new = '\n'.join(e.get('new_string', '') or '' for e in ti.get('edits', []))
        snippets, total = offenders(new)
        if total:
            deny(path, snippets, total)
    elif tool == 'Bash':
        cmd = ti.get('command', '') or ''
        if not DASH.search(cmd):
            return
        # Only when the command writes into a prose file (redirect, tee, heredoc target).
        target = re.search(r'(?:>>?|\btee\s+(?:-a\s+)?)\s*["\']?([^\s"\'|;&]+(?:' +
                           '|'.join(re.escape(e) for e in EXTS) + r'))\b', cmd, re.I)
        if target:
            snippets, total = offenders(cmd)
            if total:
                deny(target.group(1), snippets, total)


try:
    main()
except Exception:
    pass  # fail-open: a broken guard must never stop work
