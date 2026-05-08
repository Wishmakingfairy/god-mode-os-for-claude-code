# GitHub repo metadata

What to set when the repo goes public. Apply via the GitHub UI ("About" cog on the repo home page) or via `gh` CLI commands at the bottom.

## Repository description (350-char limit)

Plain text. Shows under the repo name in search results and on the repo home.

> Discipline hooks for Claude Code. Stop the agent from claiming "done" without proof, block accidental writes to ~/.claude config, and route prompts to skills via local pgvector with zero Anthropic tokens.

Length: 215 chars. Under the limit, no truncation in search.

Alternate (shorter, punchier):

> Hooks that make Claude Code stop lying about "done", plus a router that stops it from burning your quota.

Length: 105 chars. Use this if the longer one feels heavy.

## Topics (up to 20 allowed; using 12)

Order matters less than coverage. Aim for both literal product matches and category/audience matches.

```
claude-code
claude-code-hooks
ai-agents
agent-guardrails
agent-discipline
ai-hooks
pgvector
skill-router
llm-tools
developer-tools
ollama
anthropic
```

Why these:
- `claude-code`, `claude-code-hooks` cover the literal product and the integration surface
- `ai-agents`, `agent-guardrails`, `agent-discipline` cover the category for cross-discovery (Aikido, Maybe Don't, Microsoft AGT topic clusters)
- `ai-hooks`, `pgvector`, `skill-router`, `ollama` cover the technical primitives
- `llm-tools`, `developer-tools` cover broader CLI/dev-tool searches
- `anthropic` covers brand-anchored discovery

## Website link

Repo home page "website" field: leave empty for v0.1. v0.2 if traction warrants, point at a static GitHub Pages site or a redirect.

## Social preview image

GitHub uses an Open Graph image for link unfurls (Twitter, Slack, LinkedIn, HN preview).

Spec:
- 1280 x 640 px (GitHub recommendation)
- < 1 MB
- PNG or JPG
- Should show the wedge sentence and the discipline GIF first frame as a still

For v0.1, generate a static PNG using VHS or hand-compose one. Suggested layout:
- Top half: text wedge "The hooks that make Claude stop lying about done."
- Bottom half: still frame from `docs/demos/discipline.gif` showing the BLOCK message
- Bottom-right corner: "github.com/Wishmakingfairy/god-mode-os-for-claude-code" in monospace

If skipping for v0.1, GitHub falls back to the README hero GIF auto-cropped, which is acceptable but suboptimal.

## CLI commands to apply (after `gh repo create` or after pushing)

```bash
gh repo edit Wishmakingfairy/god-mode-os-for-claude-code \
    --description "Discipline hooks for Claude Code. Stop the agent from claiming 'done' without proof, block accidental writes to ~/.claude config, and route prompts to skills via local pgvector with zero Anthropic tokens." \
    --add-topic claude-code \
    --add-topic claude-code-hooks \
    --add-topic ai-agents \
    --add-topic agent-guardrails \
    --add-topic agent-discipline \
    --add-topic ai-hooks \
    --add-topic pgvector \
    --add-topic skill-router \
    --add-topic llm-tools \
    --add-topic developer-tools \
    --add-topic ollama \
    --add-topic anthropic
```

## Pinning

After launch, pin god-mode-os to your GitHub profile (Settings -> Profile -> Customize your pins). This is the single most underrated star multiplier for personal-brand-anchored repos.

## Releases

For v0.1.0, create a GitHub Release tagged `v0.1.0` with the CHANGELOG.md v0.1.0 section as the body. This makes the repo appear under GitHub's "recently released" feeds and gives users a stable artifact to install from.

```bash
gh release create v0.1.0 --title "v0.1.0" --notes-file CHANGELOG.md
```
