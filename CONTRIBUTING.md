# Contributing

Thanks for considering a contribution. This project is v0.1; the surface is small and the bar is "does it make Claude Code more honest, faster, or cheaper without adding install friction."

## Before you open a PR

- Open an issue first for anything beyond a typo or one-line fix. We agree on scope before code.
- Run `shellcheck` on every changed `.sh` file. CI will reject warnings.
- New discipline checks must default OFF. Add a `GMOS_CHECK_<name>` env var, default `0`, and document it in the README.
- Hooks must honor the kill switch (`$GMOS_KILL_SWITCH`) and the admin override (`$GMOS_ADMIN_OVERRIDE=1`).
- No new mandatory dependencies in Tier 1. `jq` and `python3` are the limit. Optional deps (Ollama, Gemini, Docker) are fine if guarded by `command -v` checks with graceful fallback.

## How a PR gets reviewed

1. Does it fix a real problem documented in an issue?
2. Does it add or break friction for a fresh-install user?
3. Does it survive `./uninstall.sh` cleanly (no leftover state)?
4. Are the changes covered by either a shell test in `tests/` or a manual repro in the PR description?

## Tests

- `tests/` runs `shellcheck` over all hooks plus a few smoke tests using `bats` (if installed).
- For new hooks, include a fixture transcript or input JSON in `docs/demos/fixtures/` and a one-liner that demonstrates the hook firing on it.

## Commit messages

One sentence. Imperative mood. No emoji. Examples:
- "Add citation check to stop-validator (off by default)"
- "Fix install.sh duplicating settings.json entries when re-run"

## Things we will not merge

- New mandatory dependencies in Tier 1
- Hooks that make outbound network calls without explicit env-var opt-in
- Cosmetic refactors that don't fix a bug or add a documented capability
- "Improvements" to the README that add words rather than remove them
