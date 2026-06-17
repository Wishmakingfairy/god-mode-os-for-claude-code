# Tiers

god-mode-os ships in two tiers. The default install (`./install.sh`) sets up Tier 1 only. Add Tier 2 later if and when you need it.

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

## Uninstall any tier

```bash
./uninstall.sh                # removes all god-mode-os hooks + plists, keeps data
./uninstall.sh --purge        # also wipes ~/.god-mode-os/ and Postgres volume
```

The Tier 1 kill switch (`bash hooks/discipline/discipline-toggle.sh off`) disables all hooks without uninstalling.
