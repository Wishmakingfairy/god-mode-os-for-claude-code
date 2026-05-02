# Changelog

## v0.1.0 (2026-04-27)

Initial public release.

### Added

- **Tier 1, Discipline**: 5 hooks (`install-guard`, `folder-law-reminder`, `stop-validator`, `session-retro`, `discipline-toggle`). Default install is hooks-only with no extra dependencies beyond `jq` and `python3`.
- **Tier 2, Routing** (opt-in): pgvector-based skill router. Local Postgres+pgvector container via Docker Compose. Indexer + query Python scripts. UserPromptSubmit hook. Sub-300ms p95 latency, zero Anthropic tokens.
- **Tier 3, Intelligence** (opt-in): daily RSS digest with Gemini synthesis fallback to raw signals; 72-hour aggregation overview. launchd job templates.
- `install.sh` with three subcommands (`discipline`, `routing`, `intelligence`, `all`). Idempotent, never duplicates settings.json entries, backs up first install.
- `uninstall.sh` with `--keep-data` (default) and `--purge` modes.
- 4 demo GIFs and 8 before/after PNGs rendered via Charm VHS.
- Configuration via env vars and dot-file configs in `~/.god-mode-os/`.
- Kill switch via `discipline-toggle.sh on|off|status`.
