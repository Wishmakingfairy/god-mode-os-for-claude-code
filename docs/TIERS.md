# Tiers

god-mode-os ships in three tiers. The default install (`./install.sh`) sets up Tier 1 only. Add Tier 2 and Tier 3 later if and when you need them.

## Tier 1, Discipline (default install, no extra deps)

What ships and how it works is documented in the [main README](../README.md). 60-second install, just `jq` + `python3` + bash.

![discipline tier demo](demos/discipline.gif)

The install-guard hook in action, blocking a write to a protected path:

![install-guard demo](demos/install-guard.gif)

## Tier 2, Routing (opt-in, requires Docker + Ollama)

Local pgvector-backed skill routing. Claude's `UserPromptSubmit` hook calls a local query that returns the top 3 skills via cosine similarity, sub-300ms, zero Anthropic tokens.

![routing tier demo](demos/routing.gif)

### Install

```bash
./install.sh routing
```

### Dependencies

- Docker (for Postgres+pgvector container)
- Ollama with `llama3.2` and `nomic-embed-text` models pulled. The setup script handles model pulls.
- Python `psycopg2-binary` (auto-installed via pip if missing)

### What ships

- `router/sql/schema.sql`: pgvector tables (`skills`, `files`), GIN indexes for BM25 hybrid.
- `router/vector/indexer.py`: walks `~/.claude/skills/` plus configurable doc folders, embeds via Ollama, upserts to Postgres.
- `router/vector/query.py`: short-prompt single-embed path, long-prompt fan-out + BM25 fused scoring path.
- `router/docker-compose.yml`: Postgres 17 + pgvector container, port 5433, volume-persisted.
- `hooks/routing/context-router.sh`: `UserPromptSubmit` hook that calls the query and injects matched skills as `additionalContext`.

### Numbers

Measured on a 721-skill corpus:
- Sub-300ms latency path
- Anthropic tokens spent on routing: 0
*(Note: Full routing accuracy benchmarks will be published in a future update)*

### Configuration

| Variable | Purpose |
|----------|---------|
| `GMOS_DB_DSN` | Postgres DSN |
| `GMOS_OLLAMA_URL` | Ollama HTTP base |
| `GMOS_EMBED_MODEL` | Embedding model (default `nomic-embed-text`) |
| `GMOS_FILE_SCOPE` | Colon-separated paths to index for files (default: skills only) |
| `GMOS_SKILL_SCOPE` | Path to `.claude/skills/` directory |

## Tier 3, Intelligence (opt-in; optional Gemini CLI)

Daily RSS digest summarized by Gemini and dropped into `~/.god-mode-os/intelligence/YYYY-MM-DD.md`. Plus a 72-hour retrospective every three days.

The digest is fired by Claude Code's `SessionStart` event — there's no clock cron. The first time you start a Claude Code session each day, the trigger checks whether today's digest exists; if not, it spawns the generator in the background and returns immediately. Skip a day of Claude Code, you don't get a stale digest.

![intelligence tier demo](demos/intelligence.gif)

### Install

```bash
./install.sh intelligence
```

### Dependencies

- Claude Code (provides the `SessionStart` event the trigger hooks into).
- Gemini CLI (optional). Without it, the digest writes raw RSS signals.

### What ships

- `hooks/intelligence/intelligence-trigger.sh`: SessionStart hook. Idempotent + async + self-throttled. Spawns the generators in background only when their output is stale.
- `hooks/intelligence/intelligence-monitor.sh`: fetches feeds and writes the day's digest.
- `hooks/intelligence/three-day-overview.sh`: 72-hour aggregator (corrections + product health + last 3 digests). Self-throttles to one run per 72h.
- `install/feeds.txt.example`: 5 feeds curated for Claude Code power users.

### Configuration

| Variable | Purpose |
|----------|---------|
| `GMOS_INTEL_DIR` | Output directory |
| `GMOS_FEEDS` | Path to feeds.txt |
| `GMOS_GEMINI_PROFILE` | One-line user profile passed to Gemini for personalized summarization |
| `GMOS_HEALTH_URLS` | Path to health-check-urls.txt for product uptime monitoring |

### Reading the digest

Each morning the digest lands as a markdown file at:

```text
~/.god-mode-os/intelligence/YYYY-MM-DD.md
```

Plus a running index at `~/.god-mode-os/intelligence/INBOX.md`.

The simplest way to read it is to drop one of these in your shell rc (`~/.zshrc` / `~/.bashrc`):

```bash
# Read today's digest in the terminal
alias digest='cat ~/.god-mode-os/intelligence/$(date +%Y-%m-%d).md'

# Open today's digest in your editor
alias digest-edit='${EDITOR:-vim} ~/.god-mode-os/intelligence/$(date +%Y-%m-%d).md'

# Pretty-print with glow if installed
alias digest='glow ~/.god-mode-os/intelligence/$(date +%Y-%m-%d).md'
```

### Send it elsewhere

The digest is just a markdown file — pipe it wherever you want.

**Post to Slack** (replace `WEBHOOK_URL` with your incoming-webhook URL):

```bash
DIGEST=~/.god-mode-os/intelligence/$(date +%Y-%m-%d).md
curl -s -X POST -H 'Content-Type: application/json' \
  --data "$(jq -Rs '{text: .}' < "$DIGEST")" \
  "$WEBHOOK_URL"
```

**Post to Discord:**

```bash
DIGEST=~/.god-mode-os/intelligence/$(date +%Y-%m-%d).md
curl -s -X POST -H 'Content-Type: application/json' \
  --data "$(jq -Rs '{content: .}' < "$DIGEST")" \
  "$DISCORD_WEBHOOK_URL"
```

**macOS desktop notification** (via `terminal-notifier`):

```bash
terminal-notifier \
  -title "god-mode-os digest" \
  -message "Today's digest is ready" \
  -open file://$HOME/.god-mode-os/intelligence/$(date +%Y-%m-%d).md
```

**Email via system `mail`** (works if your machine has a configured mailer):

```bash
mail -s "god-mode-os digest $(date +%Y-%m-%d)" you@example.com \
  < ~/.god-mode-os/intelligence/$(date +%Y-%m-%d).md
```

Drop any of these into the launchd plist as a `<key>StandardOutPath</key>` post-step or wire them as a separate hook. Native Slack / email / webhook delivery is on the v0.2 roadmap.

## Uninstall any tier

```bash
./uninstall.sh                # removes all god-mode-os hooks + plists, keeps data
./uninstall.sh --purge        # also wipes ~/.god-mode-os/ and Postgres volume
```

The Tier 1 kill switch (`bash hooks/discipline/discipline-toggle.sh off`) disables all hooks without uninstalling.
