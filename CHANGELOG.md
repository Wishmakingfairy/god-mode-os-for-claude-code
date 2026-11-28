# Changelog

## Unreleased (0.2.0)

### Added

- Installable as a Claude Code plugin (`.claude-plugin/`, `hooks/hooks.json`), next to `install.sh`.
- stop-validator: new check `GMOS_CHECK_VERIFY_CLAIM`, off by default. When switched on, a sentence that ends by saying tests, a build or lint passed is blocked if the turn held only file views and edits. It matches words, so it misses many phrasings.
- stop-validator: the final reply is now taken from the hook input. Before, the hook read the transcript, where the final reply is often not written yet, so it could judge nothing.
- `push-gate` hook, off by default. When switched on, a publish command (`git push`, `gh repo create`, `gh pr create` and similar) needs a fresh, single-use approval that names the owner and the visibility.
- `dash-guard` hook, off by default. Stops long dashes being written into files.
- Test suites in `tests/`: 298 guard cases, 38 stop-validator cases, 61 cases for the small hooks. CI runs them on Linux and macOS.
- `evals/`: 9 with/without cases for `claude plugin eval`.

### Changed

- install-guard rewritten. It now blocks only when a protected path is the target of a write, move or delete. Reading, listing or naming a protected path passes.
- install-guard: the built-in protected paths always apply; `~/.god-mode-os/protected-paths.txt` adds to them and can no longer replace them. The guard also protects its own switches. Every `CLAUDE.md` is protected by default (`GMOS_PROTECT_CLAUDE_MD=0` turns that off). Works without `jq` (python3 fallback).
- stop-validator: the file-claim check reads the whole chat and what the user typed, and ignores web addresses, quoted examples and placeholders. The statistics check passes when any tool output in the same turn holds a number. "robust" and "scalable" are no longer filler words. The contradiction check only writes to a log, it never blocks.
- folder-law-reminder warns by default. `GMOS_FOLDER_LAW=block` restores blocking.
- session-retro writes to `~/.god-mode-os/retros/<project>` by default, not into your repo. `GMOS_RETRO_IN_PROJECT=1` restores the old place, never inside a git work tree.
- capability-manifest rewritten, generic, honors the kill switch.
- Public edition is now zero-egress by default. No external network calls unless you opt in. See `PRIVACY.md`.
- `session-retro` Gemini summary is off by default. Set `GMOS_RETRO_GEMINI=1` to enable it.

### Added earlier, not yet released

- Local secret-scan pre-deploy gate: `bin/pre-deploy-gate.sh` (gitleaks, fully local; optional osv-scanner CVE lookup).
- `capability-manifest` SessionStart hook: live, local inventory of installed skills, MCP servers, and plugins.
- `PRIVACY.md` documenting the network policy and the two opt-in exceptions.
- stop-validator: AI-slop and sycophantic-opener checks, plus a 3-sample majority vote on the contradiction check to cut false positives.
- install-guard: blocks the sandbox-override flag (Claude Code issue #10089).

### Removed

- Tier 3 Intelligence (RSS + Gemini daily digest) is no longer part of the public edition.

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
