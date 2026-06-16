# Privacy and Network Policy

This edition of god-mode-os is built to be safe to run inside a company. The design rule
is simple: **by default it makes no external network calls and sends your data nowhere.**

## What runs, and where it runs

| Component | What it does | Network |
|-----------|--------------|---------|
| Discipline hooks (install-guard, stop-validator, folder-law, session-retro) | Inspect your own session locally and block rule violations | None |
| Local skill router (pgvector + Ollama) | Routes prompts to skills on your machine | Localhost only (Postgres + Ollama) |
| capability-manifest | Lists your installed skills/MCPs/plugins at session start | None (reads local files) |
| pre-deploy-gate, secret scan (gitleaks) | Scans your repo for committed secrets before deploy | None (fully local) |

## The only two things that can touch the network (both opt-in, both off by default)

- **osv-scanner** (the optional second step of the pre-deploy gate) looks up known CVEs in
  the public OSV database at `osv.dev`. It only runs if you choose to install it. It sends
  package names and versions, never your source code. Without it, the gate still works as a
  local-only secret scanner.
- **session-retro Gemini summary** is **off by default**. The session-retro hook writes a
  local retro from your own session stats with no network calls. Only if you set
  `GMOS_RETRO_GEMINI=1` does it send the session transcript to the Gemini CLI for a written
  summary. Leave it unset and nothing leaves your machine.

## What this edition does NOT do

- No telemetry, no analytics, no phone-home, ever.
- By default, no content (prompts, transcripts, files) is sent to any LLM or third-party
  service. The only exception is the opt-in `GMOS_RETRO_GEMINI=1` summary above.
- No destructive operations: hooks fail open so they never break a session, and writes to
  your `~/.claude` config are blocked unless you explicitly approve them.

## Auditing it yourself

Everything is plain bash and Python. To verify the network claim, grep the tree:

```bash
grep -rniE 'curl|wget|https?://|requests\.(post|get)|urllib|socket' --include='*.sh' --include='*.py' .
```

The only non-localhost hit you should find is the optional `osv.dev` lookup documented above.
