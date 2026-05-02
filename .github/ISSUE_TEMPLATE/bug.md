---
name: Bug report
about: A hook is misbehaving or the install/uninstall is broken
title: '[bug] '
labels: bug
---

### What happened

(One sentence. What you saw vs what you expected.)

### Steps to reproduce

1.
2.
3.

### Environment

- macOS or Linux:
- Tier installed (discipline / routing / intelligence / all):
- Output of `bash hooks/discipline/discipline-toggle.sh status`:
- Output of `jq -e '.hooks' ~/.claude/settings.json | head -40`:

### Hook output

If a hook fired unexpectedly, paste the full stderr and exit code:

```
```

### Anything that helps

(Custom config, conflicting hooks, etc.)
