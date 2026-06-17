<p align="center">
  <img src="docs/banner.png" alt="god-mode-os: Claude Code, with discipline hooks" width="100%">
</p>

# Claude Code, with discipline hooks

by [@Wishmakingfairy](https://github.com/Wishmakingfairy)

**Stop Claude Code lying about "done". Stop it burning your quota on routing.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE) [![Status: v0.1](https://img.shields.io/badge/status-v0.1-blue.svg)](CHANGELOG.md) [![macOS](https://img.shields.io/badge/platform-macOS-lightgrey.svg)](#compatibility) [![CI](https://github.com/Wishmakingfairy/god-mode-os-for-claude-code/actions/workflows/ci.yml/badge.svg)](https://github.com/Wishmakingfairy/god-mode-os-for-claude-code/actions/workflows/ci.yml)

![discipline tier demo](docs/demos/discipline.gif)

god-mode-os is a layer of bash hooks for Claude Code that:

- **Block false "done" claims.** Claude can't say it ran the tests if it never ran the tests.
- **Protect `~/.claude/`.** Writes to your hooks, skills, and `settings.json` need explicit approval.
- **Catch committed secrets before you ship.** A local, fail-closed gitleaks gate.
- **Route prompts to skills locally.** pgvector + Ollama, sub-300 ms, zero Anthropic tokens.
- **Run offline.** No telemetry, no phone-home. Your code and prompts never leave the machine.

<p align="center">
  <img src="docs/features.png" alt="Four features: blocks false done, secret-scan gate, local skill routing, runs offline" width="100%">
</p>

```bash
git clone https://github.com/Wishmakingfairy/god-mode-os-for-claude-code
cd god-mode-os-for-claude-code
./install.sh                # ~60 seconds, only jq + python3 needed
```

> **Don't trust the README?** Run `bash smoke.sh`. It tests every load-bearing claim in this README against the real code and prints a pass/fail receipt. It runs in a throwaway `HOME` and installs nothing, so you can prove the claims before you touch your own `~/.claude`. The same script runs in CI on every push, on Linux and macOS, so the badge above is a live receipt too.

## Contents

- [Runs offline](#runs-offline)
- [How it hooks in](#how-it-hooks-in)
- [What it does](#what-it-does)
- [Before / after](#before--after)
- [Install](#install)
- [What ships in the default install](#what-ships-in-the-default-install)
- [Customize](#customize)
- [FAQ](#faq)

## Why this exists

Four walls every senior Claude Code user has hit:

1. **Claude lies about "done."** It claims tests pass without running them, or claims it edited a file it never read.
2. **Skills are noise.** With hundreds of skills installed, Claude burns input tokens scanning manifests to pick the right tool, often picking the wrong one.
3. **Context dies between sessions.** Every morning the agent re-onboards on the same project.
4. **Discipline slips at 11pm.** Prompt-text rules ("verify before saying done") are ignorable. Hook-level rules are not.

god-mode-os is the discipline layer Anthropic deliberately leaves to vendors. It enforces what your `CLAUDE.md` only describes.

<p align="center">
  <img src="docs/before-after.png" alt="Claude Code alone: claims done without testing, leaks secrets, wastes tokens, rewrites config. With god-mode-os: done only after a real test, secrets caught, 0-token local routing, config edits need approval" width="100%">
</p>

## Runs offline

By default god-mode-os makes no external network calls. No telemetry, no analytics, no phone-home. Your prompts, transcripts, and code stay on your machine. The local skill router talks only to localhost (Postgres and Ollama). Two optional exceptions exist, both off by default and documented: the osv-scanner CVE lookup in the pre-deploy gate, and a Gemini session summary you turn on with `GMOS_RETRO_GEMINI=1`. Full detail in [PRIVACY.md](PRIVACY.md). Verify it yourself: `grep -rniE 'curl|wget|https?://' --include='*.sh' --include='*.py' .` and you will find only localhost and the documented osv.dev lookup.

## How it hooks in

god-mode-os attaches a small bash hook to each point in the Claude Code session lifecycle. Nothing runs in the background and nothing leaves your machine.

<p align="center">
  <img src="docs/lifecycle.png" alt="god-mode-os hooks into the Claude Code session lifecycle: capability-manifest on SessionStart, context-router on UserPromptSubmit, install-guard and folder-law on PreToolUse, stop-validator and session-retro on Stop" width="100%">
</p>

## What it does

The table below summarises the four scenarios in the [before / after](#before--after) section. Each row links to a runnable fixture in [`docs/demos/fixtures/`](docs/demos/fixtures/) so you can reproduce locally.

| Scenario | Default Claude Code (typical) | With god-mode-os |
|---|---|---|
| [stop-validator](#stop-validator-stops-claude-lying-about-done) | "All tests pass. Done." with no tool use to back it | block fires; agent rewrites with `Read` + actual test run |
| [install-guard](#install-guard-stops-silent-rewrites-of-your-claude-code-config) | `Write` to `~/.claude/settings.json` proceeds; existing entries can be dropped | blocked until `GMOS_ADMIN_OVERRIDE=1` |
| [routing](#routing-skill-selection-at-zero-anthropic-tokens-tier-2) | Claude reads the full skill manifest each prompt to pick (~721 descriptions in the author's config) | local pgvector cosine match: **0 Anthropic tokens** by design, **sub-300 ms typical** on the author's setup |
| secret-scan gate | a committed API key reaches the remote before anyone notices | `bin/pre-deploy-gate.sh` blocks the deploy on any gitleaks hit, fully local |

**Routing per prompt, lower is better.** The saving scales with how many skills you run. The figures below are estimates for a setup with hundreds of skills; with only a few, the difference is small.

<p align="center">
  <img src="docs/compare.png" alt="Routing cost per prompt: default sends ~3,200 tokens, ~2.4s, ~$0.0096; god-mode-os sends 0 tokens, 0.26s, $0.00" width="100%">
</p>

## Before / after

Each pair below is a screen recording of a fixture script in [`docs/demos/fixtures/`](docs/demos/fixtures/). The fixtures *depict* the scenario the hook is meant to address; the hooks themselves are real bash and run against your live Claude Code sessions (verify with `./install.sh && cat ~/.claude/hooks/`). Left: default Claude Code behaviour. Right: same prompt with god-mode-os installed.

### stop-validator: stops Claude lying about "done"

> Prompt: "Fix the JWT bug in `~/src/auth.ts` and run the tests." A known Claude Code failure mode: the agent says "all tests pass, done" without actually running them, and you ship the regression. The stop-validator hook blocks any final response that claims about a file path without a recent `Read` / `Grep` / `Bash` of that path. Claude is forced to rewrite the response with proof.

<table width="100%">
<tr>
<td width="50%"><img src="docs/demos/before-after/discipline-before.png" alt="Without god-mode-os: Claude claims All tests pass, Done. Three hours later production breaks at /auth/login." /></td>
<td width="50%"><img src="docs/demos/before-after/discipline-after.png" alt="With god-mode-os: STOP VALIDATOR BLOCK fires, Claude is forced to read, edit, run pnpm test, show 10 of 10 passed, then claim done." /></td>
</tr>
</table>

### install-guard: stops silent rewrites of your Claude Code config

> Prompt: "Add a new PostToolUse hook to my Claude Code config." Without a guard, an agent with `Write` access on `~/.claude/settings.json` can re-serialise the file with new entries, and risk dropping or malforming the existing ones. With the install-guard hook, any `Write` / `Edit` / `Bash` against `~/.claude/settings.json`, `~/.claude/hooks/`, or `~/.claude/skills/` is blocked until the user re-runs with `GMOS_ADMIN_OVERRIDE=1`.

<table width="100%">
<tr>
<td width="50%"><img src="docs/demos/before-after/install-guard-before.png" alt="Without god-mode-os: Claude writes to settings.json, merges with malformed indentation, drops two existing Stop hooks. Discovered later via a bug." /></td>
<td width="50%"><img src="docs/demos/before-after/install-guard-after.png" alt="With god-mode-os: INSTALL CONFIG GUARD BLOCK fires, Claude surfaces it for approval, only after explicit override does the write happen." /></td>
</tr>
</table>

### routing: skill selection at zero Anthropic tokens (Tier 2)

> Prompt: "design system tokens for a dark dashboard." Without the hook, Claude reads the skill manifest each prompt to pick. At 721 skills, this is around 3,200 input tokens / ~2.4 s / ~$0.0096 per query (estimate, varies with manifest size and prompt length). With the hook, the router uses a local pgvector cosine match. The architecture sends **0 Anthropic tokens** for routing (no API call is made). The latency on the author's setup is **sub-300 ms** typical; the live measurement loop is in [`docs/demos/fixtures/router-demo.sh`](docs/demos/fixtures/router-demo.sh).

<p align="center">
  <img src="docs/flow-local.png" alt="Your prompt goes to a local router (pgvector + Ollama) that picks the right skill on your machine. The Anthropic API is not called to route, so 0 tokens are spent and your data stays local" width="100%">
</p>

<table width="100%">
<tr>
<td width="50%"><img src="docs/demos/before-after/routing-before.png" alt="Without god-mode-os: Claude reads 721 skill manifest, picks 5 candidates, evaluates each. 3,200 input tokens, 2.4 seconds, $0.0096 per query, ~$0.50 per day at 50 queries." /></td>
<td width="50%"><img src="docs/demos/before-after/routing-after.png" alt="With god-mode-os: pgvector cosine match in 259ms, picks theming-system/design-token/dark-mode-design, 0 tokens, 0.26 seconds, $0.00." /></td>
</tr>
</table>

### secret-scan gate: catch committed secrets before deploy

> Prompt: "ship the new env config." A common failure: a real API key gets committed and pushed before anyone reads the diff. Run `bin/pre-deploy-gate.sh` first. It runs gitleaks locally over the working tree and exits non-zero on any hit, so the deploy stops before the secret leaves your machine. gitleaks is fully local. The optional second step (osv-scanner CVE lookup) is the only part that touches the network, and only if you install it.

```bash
bin/pre-deploy-gate.sh .        # exit 0 = clean, exit 1 = secret or CVE found
```

Real output on a clean tree:

```text
============================================
 PRE-DEPLOY SECURITY GATE  ::  .
============================================

--- [1/2] Secret scan (gitleaks, local) ---
  OK: no secrets found

--- [2/2] Dependency CVEs (osv-scanner, optional, online) ---
  OK: no known-vulnerable dependencies

============================================
 GATE PASSED
============================================
```

When gitleaks finds a key, that step prints `FAIL: secrets detected, do not deploy` and the gate exits `1`, so a CI step or a pre-push wrapper stops the deploy before the secret leaves your machine.

## Install

The install command is above. To recap the steps:

1. `./install.sh` symlinks six hooks into `~/.claude/hooks/` and registers five entries in `~/.claude/settings.json`.
2. The first install backs up your existing `settings.json` to `settings.json.gmos-backup`.
3. Restart Claude Code to activate.
4. To remove cleanly: `./uninstall.sh` (data kept) or `./uninstall.sh --purge` (data wiped). Or `bash hooks/discipline/discipline-toggle.sh off` for the kill switch without uninstalling.

Want the local skill router? See [TIERS.md](docs/TIERS.md).

### Try it before you trust it, no install

`smoke.sh` runs every load-bearing claim in this README against the real code, in a throwaway `HOME`. It installs nothing and never touches your real `~/.claude` or `~/.god-mode-os`, so you can prove the claims first and decide after.

```bash
git clone https://github.com/Wishmakingfairy/god-mode-os-for-claude-code
cd god-mode-os-for-claude-code
bash smoke.sh            # plain pass/fail receipt
bash smoke.sh -v         # verbose: shows how each check was performed
```

<p align="center">
  <img src="docs/proof.png" alt="smoke.sh receipt: 21 claims verified, 0 warnings, 0 failed; every load-bearing README claim true on this machine" width="92%">
</p>

It hard-fails (exit 1) on any false behavioural claim and soft-warns on timing. The same script runs in CI on every push, on Linux and macOS, so the badge at the top is a live receipt too.

## What ships in the default install

The discipline tier hooks Claude Code's `Stop` and `PreToolUse` events.

- **stop-validator** blocks the response when Claude claims about a file path without a recent `Read`/`Grep`/`Bash` of it, contains an em-dash, makes statistical claims without a source, or contradicts an earlier turn. Claude is forced to rewrite with proof.
- **install-guard** blocks `Write`/`Edit`/`Bash` calls that target `~/.claude/settings.json`, `~/.claude/hooks/`, `~/.claude/skills/`, and other protected paths. Override per command with `GMOS_ADMIN_OVERRIDE=1`.
- **folder-law-reminder** blocks writes to `/tmp` and `~/Downloads` by default. Customize via `~/.god-mode-os/forbidden-write-paths.txt`.
- **session-retro** auto-writes `docs/retros/YYYY-MM-DD-topic.md` when a session uses 5 or more tools. It writes from local session stats. An optional Gemini summary is off by default; set `GMOS_RETRO_GEMINI=1` to turn it on (that step sends the transcript to the Gemini CLI).
- **capability-manifest** runs at `SessionStart` and injects a live, local list of your installed skills, MCP servers, and plugins, so Claude does not falsely claim it lacks a tool it actually has. No network calls.
- **discipline-toggle** is the kill switch: `bash hooks/discipline/discipline-toggle.sh off`.

Seven toggle env vars, all default on:

```text
GMOS_CHECK_EM_DASH       em-dash hard ban
GMOS_CHECK_SLOP          ban AI-slop filler words
GMOS_CHECK_SYCOPHANCY    ban sycophantic openers
GMOS_CHECK_TOOL_USE      no claims about files without reading
GMOS_CHECK_CITATIONS     statistics need a source
GMOS_CHECK_CONSISTENCY   detect contradiction with prior turn (requires Ollama, majority vote)
GMOS_CHECK_DODGE         detect capability denial (requires Ollama)
```

Set any to `0` to disable that check. The two Ollama-dependent checks self-disable silently if `ollama` is not on `PATH`, so the default install with just `jq` and `python3` runs the first three out of the box.

## Customize

Everything is configurable via either an env var or a plain text file in `~/.god-mode-os/`. Edit, save, restart Claude Code; nothing to redeploy.

| What you can change | Where | Default |
|---|---|---|
| Which discipline checks fire | `GMOS_CHECK_*` env vars | all 5 on |
| Paths install-guard protects | `~/.god-mode-os/protected-paths.txt` | `~/.claude/{settings.json, hooks/, skills/, plugins/, commands/}` |
| Paths folder-law-reminder blocks | `~/.god-mode-os/forbidden-write-paths.txt` | `/tmp` and `~/Downloads` |
| Postgres DSN, Ollama URL, embed model (Tier 2) | `GMOS_DB_DSN`, `GMOS_OLLAMA_URL`, `GMOS_EMBED_MODEL` env vars | localhost defaults |
| Kill switch (disable everything, no uninstall) | `~/.claude/.god-mode-disabled` (touch to enable) | absent |
| Per-command escape hatch | `GMOS_ADMIN_OVERRIDE=1` | unset |

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

## Known limits

What it does not do, stated plainly:

- It constrains behavior. It does not make Claude smarter. These are bash hooks, not a model upgrade.
- stop-validator catches a pattern: claims about a file with no recent read or test, em dashes, unsourced stats, contradictions, slop words. It will not catch every false "done", and the two Ollama-based checks can throw false positives. Every check is an env-var toggle you can turn off.
- The routing token saving scales with how many skills you run. With a handful of skills it is small.
- The secret gate catches what gitleaks recognizes, not literally every secret. The optional osv-scanner step is the only part that touches the network.
- macOS first. The discipline tier is portable bash; the routing tier needs Docker and Ollama.
- It is not a security boundary against a malicious local user. If someone has your shell, they have your config.

## Compatibility

Tested on macOS. Tier 1 hooks should work on Linux unchanged. Notifications use `terminal-notifier` on macOS; on Linux substitute `notify-send`.

## Contributing

v0.1. Issues, ideas, and PRs welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). New discipline checks must be opt-in by default.

## Author

Built by **Harald Gabrans Zukovs** ([@Wishmakingfairy on GitHub](https://github.com/Wishmakingfairy) · [LinkedIn](https://linkedin.com/in/haraldsgabrans)).

If god-mode-os saves you time, the cheapest way to say thanks is to star the repo, file a real-use issue, or share what broke and how you fixed it. PRs welcome under [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE).

## Credits

Built on top of [Claude Code](https://docs.claude.com/en/docs/agents-and-tools/claude-code/overview), [pgvector](https://github.com/pgvector/pgvector), and [Ollama](https://ollama.com). Demo GIFs were rendered with [Charm VHS](https://github.com/charmbracelet/vhs) during development; users do not need it installed.

---

If `bash smoke.sh` printed `Every load-bearing README claim is TRUE on this machine`, that took 90 seconds and it never lied to you once. Star the repo. Then go install it.
