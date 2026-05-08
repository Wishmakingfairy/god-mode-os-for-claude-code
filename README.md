# Claude Code, with discipline hooks

The hooks that make Claude Code stop lying about "done", plus a router that stops it from burning your quota.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE) [![Status: v0.1](https://img.shields.io/badge/status-v0.1-blue.svg)](CHANGELOG.md) [![macOS](https://img.shields.io/badge/platform-macOS-lightgrey.svg)](#compatibility)

![discipline tier demo](docs/demos/discipline.gif)

## Why this exists

Four walls every senior Claude Code user has hit:

1. **Claude lies about "done."** It claims tests pass without running them, or claims it edited a file it never read.
2. **Skills are noise.** With hundreds of skills installed, Claude burns input tokens scanning manifests to pick the right tool, often picking the wrong one.
3. **Context dies between sessions.** Every morning the agent re-onboards on the same project.
4. **Discipline slips at 11pm.** Prompt-text rules ("verify before saying done") are ignorable. Hook-level rules are not.

god-mode-os is the discipline layer Anthropic deliberately leaves to vendors. It enforces what your `CLAUDE.md` only describes.

## By the numbers

Real numbers from the four sample sessions in the [before / after](#before--after) section below.

| | Without god-mode-os | With god-mode-os |
|---|---|---|
| False "done" claims caught | none (you find out via prod bug 3 hours later) | every one (block + forced re-run with proof) |
| Routing tokens per prompt | ~3,200 input tokens | 0 (local pgvector) |
| Routing latency per prompt | ~2.4 s | ~0.26 s |
| Anthropic spend on routing (50 prompts/day) | ~$0.50 | $0.00 |
| Daily intelligence scan | 5 tabs, ~25 min, ~120 items | one digest file, ~90 s, sorted "must read" / "skip" |
| `~/.claude/` config rewrites | silent (lost hooks, bug next session) | blocked, explicit approval required |

## Before / after

Each pair below is a real terminal session running a fixture in `docs/demos/fixtures/`. Left: default Claude Code. Right: same prompt with god-mode-os installed. Click any image to view full size.

### stop-validator: stops Claude lying about "done"

> Prompt: "Fix the JWT bug in `~/src/auth.ts` and run the tests." Without the hook, Claude claims everything passes and you ship. With the hook, the response is blocked until Claude actually `Read`s the file, runs tests, and shows the output.

<table width="100%">
<tr>
<td width="50%"><img src="docs/demos/before-after/discipline-before.png" alt="Without god-mode-os: Claude claims All tests pass, Done. Three hours later production breaks at /auth/login." /></td>
<td width="50%"><img src="docs/demos/before-after/discipline-after.png" alt="With god-mode-os: STOP VALIDATOR BLOCK fires, Claude is forced to read, edit, run pnpm test, show 10 of 10 passed, then claim done." /></td>
</tr>
</table>

### install-guard: stops silent rewrites of your Claude Code config

> Prompt: "Add a new PostToolUse hook to my Claude Code config." Without the hook, Claude rewrites `settings.json` directly and clobbers two of your existing Stop hooks; you find out via a bug next session. With the hook, the write is blocked until you explicitly approve via `GMOS_ADMIN_OVERRIDE=1`.

<table width="100%">
<tr>
<td width="50%"><img src="docs/demos/before-after/install-guard-before.png" alt="Without god-mode-os: Claude writes to settings.json, merges with malformed indentation, drops two existing Stop hooks. Discovered later via a bug." /></td>
<td width="50%"><img src="docs/demos/before-after/install-guard-after.png" alt="With god-mode-os: INSTALL CONFIG GUARD BLOCK fires, Claude surfaces it for approval, only after explicit override does the write happen." /></td>
</tr>
</table>

### routing: skill selection at zero Anthropic tokens (Tier 2)

> Prompt: "design system tokens for a dark dashboard." Without the hook, Claude reads all 721 skill descriptions every prompt = ~3,200 input tokens, ~2.4s, ~$0.50/day on routing alone. With the hook, a local pgvector lookup picks the top three skills in 259 ms with 0 Anthropic tokens.

<table width="100%">
<tr>
<td width="50%"><img src="docs/demos/before-after/routing-before.png" alt="Without god-mode-os: Claude reads 721 skill manifest, picks 5 candidates, evaluates each. 3,200 input tokens, 2.4 seconds, $0.0096 per query, ~$0.50 per day at 50 queries." /></td>
<td width="50%"><img src="docs/demos/before-after/routing-after.png" alt="With god-mode-os: pgvector cosine match in 259ms, picks theming-system/design-token/dark-mode-design, 0 tokens, 0.26 seconds, $0.00." /></td>
</tr>
</table>

### intelligence: daily digest replaces tab-juggling (Tier 3)

> Without the hook, you open five RSS/news tabs every morning and scan 120 items for 25 minutes; you keep maybe 5 minutes of signal. With the hook, a single file lands at 7am with "must read" and "skip" pre-tagged.

<table width="100%">
<tr>
<td width="50%"><img src="docs/demos/before-after/intelligence-before.png" alt="Without god-mode-os: 5 tabs open, scan 120 items, 25 minutes reading, only 5 minutes worth of signal kept." /></td>
<td width="50%"><img src="docs/demos/before-after/intelligence-after.png" alt="With god-mode-os: one digest file at 7am, must-read and skip pre-tagged, 90 seconds to read, INBOX.md keeps the index." /></td>
</tr>
</table>

## Install

```bash
git clone https://github.com/Wishmakingfairy/god-mode-os
cd god-mode-os
./install.sh
```

That installs the discipline hooks into `~/.claude/hooks/` and registers them in `~/.claude/settings.json`. ~60 seconds, no extra dependencies beyond `jq` and `python3`. Restart Claude Code to activate.

Want the local skill router or daily intelligence digest? See [TIERS.md](docs/TIERS.md).

## What ships in the default install

The discipline tier hooks Claude Code's `Stop` and `PreToolUse` events.

- **stop-validator** blocks the response when Claude claims about a file path without a recent `Read`/`Grep`/`Bash` of it, contains an em-dash, makes statistical claims without a source, or contradicts an earlier turn. Claude is forced to rewrite with proof.
- **install-guard** blocks `Write`/`Edit`/`Bash` calls that target `~/.claude/settings.json`, `~/.claude/hooks/`, `~/.claude/skills/`, and other protected paths. Override per command with `GMOS_ADMIN_OVERRIDE=1`.
- **folder-law-reminder** blocks writes to `/tmp` and `~/Downloads` by default. Customize via `~/.god-mode-os/forbidden-write-paths.txt`.
- **session-retro** auto-writes `docs/retros/YYYY-MM-DD-topic.md` when a session uses 5 or more tools. Uses Gemini for synthesis if installed, raw stats otherwise.
- **discipline-toggle** is the kill switch: `bash hooks/discipline/discipline-toggle.sh off`.

Five toggle env vars, all default on:

```text
GMOS_CHECK_EM_DASH       em-dash hard ban
GMOS_CHECK_TOOL_USE      no claims about files without reading
GMOS_CHECK_CITATIONS     statistics need a source
GMOS_CHECK_CONSISTENCY   detect contradiction with prior turn (requires Ollama)
GMOS_CHECK_DODGE         detect capability denial (requires Ollama)
```

Set any to `0` to disable that check. The two Ollama-dependent checks self-disable silently if `ollama` is not on `PATH`, so the default install with just `jq` and `python3` runs the first three out of the box.

## Who this is for

You probably want this if you run Claude Code more than 3 hours a day, you have blown through your Max quota and don't know where the tokens went, you have caught Claude claiming "all tests pass" when they didn't, or you have rebuilt your own hook setup at least once.

You probably don't want this if you use Claude Code casually, you don't have `jq` installed, or you think hooks are over-engineering.

## FAQ

### What does god-mode-os do?

god-mode-os installs bash hooks into `~/.claude/hooks/` that intercept Claude Code at the `Stop`, `PreToolUse`, and `UserPromptSubmit` events. The hooks enforce verification before "done" claims, block writes to protected config paths, and (optionally, see [TIERS.md](docs/TIERS.md)) route prompts to skills via local pgvector with zero Anthropic API tokens.

### How does it stop Claude from lying about "done"?

The stop-validator hook reads the last assistant turn from the session transcript and blocks it (exit code 2 plus stderr) if the response claims about a file path without a recent `Read`/`Grep`/`Bash` of that path, contains an em-dash, makes a statistical claim without a source, or contradicts an earlier turn. Claude Code surfaces the stderr as a system reminder, forcing the agent to rewrite the response with proof.

### Does this work with Claude Pro / Max, or only the API?

god-mode-os works with both Claude Pro / Max subscriptions and the Claude API. Hooks run locally in your shell; they don't care about billing.

### Will my existing hooks still work?

god-mode-os adds new entries to `settings.json` without modifying or removing existing ones. The first install creates a backup at `~/.claude/settings.json.gmos-backup` so you can revert if needed.

### Can the agent bypass the hooks?

The agent cannot bypass hooks. Hooks run in your shell process, outside Claude's context window. The agent can request the user to set `GMOS_ADMIN_OVERRIDE=1` for a specific command, which is the intended escape hatch.

### How do I uninstall?

Run `./uninstall.sh` to remove hooks and settings.json entries (data kept). Run `./uninstall.sh --purge` to also wipe `~/.god-mode-os/`. The kill switch `bash hooks/discipline/discipline-toggle.sh off` disables all hooks without uninstalling.

## Compatibility

Tested on macOS. Tier 1 hooks should work on Linux unchanged. Notifications use `terminal-notifier` on macOS; on Linux substitute `notify-send`.

## Contributing

v0.1. Issues, ideas, and PRs welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). New discipline checks must be opt-in by default.

## License

[MIT](LICENSE).

## Credits

Built on top of [Claude Code](https://docs.claude.com/en/docs/agents-and-tools/claude-code/overview), [pgvector](https://github.com/pgvector/pgvector), and [Ollama](https://ollama.com). Demo GIFs were rendered with [Charm VHS](https://github.com/charmbracelet/vhs) during development; users do not need it installed.

---

Star this repo if it saved you a "done" you would have shipped without proof.
