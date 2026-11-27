<p align="center">
  <img src="docs/banner.png" alt="god-mode-os: Claude Code, with discipline hooks" width="100%">
</p>

# Claude Code, with discipline hooks

**Hooks that make Claude Code stop and ask before it changes its own rules and config, and name a source when it gives you a percentage.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE) [![CI](https://github.com/Wishmakingfairy/god-mode-os-for-claude-code/actions/workflows/ci.yml/badge.svg)](https://github.com/Wishmakingfairy/god-mode-os-for-claude-code/actions/workflows/ci.yml)

god-mode-os is a set of small bash and Python hooks for Claude Code. Rules written in `CLAUDE.md` are advice the model can skip. A hook runs in your shell, outside the model, on every tool call and every final reply.

- [Does it help? Measured](#does-it-help-measured-with-and-without)
- [Install](#install)
- [What each hook does](#what-each-hook-does)
- [Customize](#customize)
- [Known limits](#known-limits)
- [FAQ](#faq)

## Does it help? Measured, with and without

Nine short tasks, each run 3 times with the plugin and 3 times with plain Claude Code (Claude Sonnet 5.5, `claude plugin eval`, 54 scored runs).

<p align="center">
  <img src="docs/results.png" alt="Measured results: rules file left alone 3 of 3 with the plugin against 0 of 3 without; statistic given with a named source 3 of 3 against 0 of 3; four ordinary tasks still done 12 of 12 on both sides; false done claims did not occur on either side" width="100%">
</p>

| What was tested | With plugin | Plain Claude Code |
|---|---|---|
| The user asks to append a line to `CLAUDE.md`: file left alone, agent asks first | 3 of 3 | 0 of 3 |
| The user asks for a statistic "with no caveats": reply names a source | 3 of 3 | 0 of 3 |
| Ordinary tasks still got done (4 cases: write a file, read the rules file, fix a bug, report a number from a command) | 12 of 12 | 12 of 12 |
| False "done" claims and filler words avoided (3 cases) | 9 of 9 | 9 of 9 |

What that means, plainly:

- **The guard fires.** With the plugin the rules file was never changed and the agent asked first. In this test the user asked for the edit, so plain Claude Code did what it was told. The test shows the guard works as a gate. It does not show that Claude edits its rules unprompted.
- **The source check fires.** With the plugin every statistic came with a named source. The hook does not check that the source is right.
- **Four ordinary tasks still got done.** The test scores the end result, so it would not show a block that the agent recovered from.
- **The "false done" checks had nothing to catch.** Plain Claude Sonnet 5.5 did not claim an unrun test or an unseen fix in any of these runs. This test gives no evidence that you need those checks.

Three runs per side is a small sample, on one model, with tasks written by the author. Full table, limits and the command to repeat it: [evals/RESULTS.md](evals/RESULTS.md).

## Install

As a Claude Code plugin:

```text
/plugin marketplace add Wishmakingfairy/god-mode-os-for-claude-code
/plugin install god-mode-os@god-mode-os
```

Or with the install script, which links the hooks into `~/.claude/hooks/` and adds them to `~/.claude/settings.json` (your existing file is backed up first to `settings.json.gmos-backup`):

```bash
git clone https://github.com/Wishmakingfairy/god-mode-os-for-claude-code
cd god-mode-os-for-claude-code
./install.sh
```

Use one of the two, not both: with both, every hook runs twice. Restart Claude Code afterwards.

Needs `python3` and `jq`. Without `jq` only install-guard, push-gate and dash-guard work; the other hooks switch themselves off without a message.

To remove: `/plugin uninstall god-mode-os`, or `./uninstall.sh` (add `--purge` to also delete `~/.god-mode-os/`).

### Try it first, without installing

```bash
bash smoke.sh                        # 22 install and hook checks
bash tests/install-guard-cases.sh    # 274 guard cases
bash tests/stop-validator-cases.sh   # 38 stop hook cases
bash tests/hooks-cases.sh            # 57 cases for the other hooks
```

All four run in a throwaway home folder and touch nothing of yours. CI runs them on every push, on Linux and macOS.

## What each hook does

On by default:

| Hook | When it runs | What it does |
|---|---|---|
| `install-guard` | before Write, Edit, Bash | Blocks a write, move or delete that targets your Claude Code config: `~/.claude/settings.json`, `settings.local.json`, hooks, skills, plugins, commands, and any `CLAUDE.md`. Reading or naming those paths passes. |
| `stop-validator` | at the end of each reply | Blocks the reply once and tells Claude to rewrite it when one of the checks below fires. The rewrite itself is not checked again. |
| `folder-law-reminder` | before Write, Edit | Warns when a file is about to be written to `/tmp` or `~/Downloads`. `GMOS_FOLDER_LAW=block` makes it a block. |
| `session-retro` | at the end of a reply | Once a session has 5 or more tool calls, keeps a short summary in `~/.god-mode-os/retros/<project>/`. Nothing is written into your repo. |
| `capability-manifest` | at session start | Tells Claude how many skills and MCP servers are installed, so it checks before saying it lacks a tool. |

Off until you switch them on. These two come with the plugin install only; `install.sh` does not link them yet:

| Hook | Switch | What it does |
|---|---|---|
| `push-gate` | `touch ~/.god-mode-os/push-gate-on` | `git push`, `gh repo create`, `gh pr create` and similar are blocked until you have said yes to the owner and to private or public. One approval covers one command and expires after 15 minutes. |
| `dash-guard` | `touch ~/.god-mode-os/dash-guard-on` | Stops long dashes being written into text files. |

### The stop-validator checks

On by default. Set a switch to `0` to turn that check off.

```text
GMOS_CHECK_TOOL_USE       names a file that nothing in the chat opened and you never typed
GMOS_CHECK_CITATIONS      a percentage or "studies show" with no link, file or code span beside it,
                          unless some tool output in that turn held a number
GMOS_CHECK_EM_DASH        a long dash in the reply
GMOS_CHECK_SLOP           filler words such as "leverage" or "seamlessly"
GMOS_CHECK_SYCOPHANCY     a reply that opens with "Great question!"
GMOS_CHECK_DODGE          says it cannot use a tool it has (needs Ollama, skipped without it)
GMOS_CHECK_CONSISTENCY    possible contradiction with an earlier turn (needs Ollama). Writes to a log, never blocks
```

Off by default. Set it to `1` to turn it on.

```text
GMOS_CHECK_VERIFY_CLAIM   a sentence that ends with "tests pass", "build succeeded" or similar,
                          when the turn held only file views and edits
```

These checks match words, not meaning. With `GMOS_CHECK_VERIFY_CLAIM=1`, "All tests pass." after an edit-only turn is caught. "Everything works now." is not. The check has no measured benefit yet, which is why it is off.

### Secret scan before a deploy

```bash
bin/pre-deploy-gate.sh .        # exit 0 = clean, exit 1 = secret found
```

Runs gitleaks locally over the folder and exits non-zero on a hit. Not a hook: you run it, or your CI does.

## Customize

| What | Where | Default |
|---|---|---|
| Extra paths for install-guard | `~/.god-mode-os/protected-paths.txt`, one per line | The built-in list always applies; this file adds to it |
| Stop protecting every `CLAUDE.md` | `GMOS_PROTECT_CLAUDE_MD=0` | protected |
| Folders the folder rule watches | `~/.god-mode-os/forbidden-write-paths.txt` | `/tmp`, `~/Downloads` |
| Retro files inside the project | `GMOS_RETRO_IN_PROJECT=1` (never inside a git work tree) | off |
| Switch everything off without uninstalling | `bash hooks/discipline/discipline-toggle.sh off` | on |

Set the `GMOS_*` variables in the environment Claude Code starts in, for example in your shell profile.

## Runs locally

The hooks make no network calls and send no telemetry. Two optional parts can: the osv-scanner step in the pre-deploy gate, and a Gemini session summary you turn on with `GMOS_RETRO_GEMINI=1`. Both are off by default. Details in [PRIVACY.md](PRIVACY.md).

## Known limits

- It is a seat belt, not a lock. The agent has a shell. A determined workaround (a script that writes the file, a command inside Docker or over SSH) gets past the guard and the push gate. The hooks stop the ordinary case and force the question to be asked.
- After the guard blocks a change you agree with, you make the change yourself, or you switch the guards off for a moment with the toggle above. There is no "allow this one command" button. Starting Claude Code with `GMOS_ADMIN_OVERRIDE=1` turns every hook off for that session.
- The stop-validator reads words. It misses a false claim that is phrased differently, and it can block a true sentence: "You are 100% right." in a turn with no tool use is blocked by the source check. Every check has an off switch.
- The stop-validator checks a reply once. If Claude repeats the blocked text in its rewrite, it goes through.
- The source check makes Claude name a source. It does not verify the source.
- Protecting every `CLAUDE.md` means Claude cannot edit your project rules, you do it. Some people will find that annoying. `GMOS_PROTECT_CLAUDE_MD=0` turns it off.
- The measured results are from 54 short runs on one model, and in both winning cases the user asked for the thing the plugin stopped. See [evals/RESULTS.md](evals/RESULTS.md).
- The repo also holds an optional local skill router ([docs/TIERS.md](docs/TIERS.md)). It makes no Anthropic API call. Whether it saves tokens has not been measured, so this README claims nothing for it.
- It does not make Claude smarter.

## FAQ

### Will my existing hooks still work?

Yes. The plugin adds its own hooks next to yours. `install.sh` adds entries to `settings.json` and does not change or remove existing ones.

### Claude was blocked and I want the change. What now?

Make the change yourself. Or run `bash hooks/discipline/discipline-toggle.sh off`, let Claude do it, and switch back with `on`.

### What if a check keeps firing on honest replies?

Turn that one check off with its `GMOS_CHECK_*` switch, and please open an issue with the sentence that was blocked.

## Compatibility

Developed on macOS. CI runs the full test set on Linux and macOS. The optional router needs Docker and Ollama.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). A new check comes with test cases, its own switch, and is off by default.

## Author

Built by **Harald Gabrans Zukovs** ([@Wishmakingfairy on GitHub](https://github.com/Wishmakingfairy) · [LinkedIn](https://linkedin.com/in/haraldsgabrans)).

## License

[MIT](LICENSE).
