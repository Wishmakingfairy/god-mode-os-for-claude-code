# Security

god-mode-os is a set of bash hooks that run inside your Claude Code sessions. It has access to whatever your Claude Code session has access to. Treat it accordingly.

## Threat model

god-mode-os is designed to defend against accidental damage by AI agents (false "done" claims, accidental config rewrites, runaway routing token spend). It is not designed to defend against a malicious local user with shell access; if an attacker has shell access, they own your config regardless.

## What god-mode-os does and does not do

- **Does**: read your `~/.claude/` config files, write logs to `~/.god-mode-os/`, register hooks in `~/.claude/settings.json`, optionally run a local Postgres+pgvector container (Tier 2), optionally schedule launchd jobs (Tier 3).
- **Does not**: phone home, send telemetry, read project source code outside the indexed scope, modify files outside `~/.god-mode-os/` and `~/.claude/hooks/` (symlinks only).
- **Outbound network calls**: only Claude Code itself talks to Anthropic. The router talks only to localhost Ollama and Postgres. The Tier 3 intelligence-monitor fetches RSS feeds (publicly addressable URLs you configure) and optionally calls Gemini CLI.

## What the install script touches

- `~/.claude/hooks/`: creates symlinks to scripts in this repo. Existing files are not modified.
- `~/.claude/settings.json`: adds entries via `jq`. First run creates a backup at `settings.json.gmos-backup`.
- `~/.god-mode-os/`: created on demand. All state, logs, retros, digests live here.
- `~/Library/LaunchAgents/com.god-mode-os.*.plist` (Tier 3 only): scheduled jobs.

## Reporting vulnerabilities

Open a private security advisory on GitHub or email the maintainer. Do not file public issues for security bugs.

In scope:
- A hook that bypasses its kill switch
- A hook that elevates privileges or escapes the user's shell context
- An install/uninstall flow that leaves dangerous state behind
- A way for a malicious agent prompt to invoke arbitrary code outside the documented hook surface

Out of scope:
- An agent finding the documented `GMOS_ADMIN_OVERRIDE=1` escape hatch (this is intended)
- A user with shell access modifying their own config

## Reviewing the source before installing

Strongly recommended for any tool that touches `~/.claude/`. Specifically read:
- `install.sh` and `uninstall.sh`
- Each hook in `hooks/discipline/`, `hooks/routing/`, `hooks/intelligence/`
- The `.plist.example` files if you install Tier 3

The repo is small. A 30-minute audit is enough to verify the hooks do what the README says.
