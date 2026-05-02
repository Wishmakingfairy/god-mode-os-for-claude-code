# Launch sequence

The plan to ship god-mode-os v0.1 publicly without burning a quarter on it.

Total budget: 1 week prep, 1 day launch, 1 week reply, then back to revenue work.

---

## T minus 7 days: pre-launch checklist

All items before any public link goes out.

### Repo hygiene
- [ ] `git status` clean. No leftover scratch files.
- [ ] `./install.sh discipline` works on a fresh test user (use a temp HOME or another Mac).
- [ ] `./uninstall.sh` cleans up every file `install.sh` created. Verified by `find ~/.claude/hooks/ ~/.god-mode-os/`.
- [ ] CI green on a fresh push (shellcheck + json + python + install-dryrun).
- [ ] All 4 hero GIFs render fresh from their tape files.
- [ ] All 4 before/after PNG pairs are committed.
- [ ] Repo description set (see CP18 / GitHub-topics.md).
- [ ] License file present and dated 2026.
- [ ] No Harald-personal paths or names anywhere in tracked files (`grep -rE 'haralds45224|Harald|Diana|Moracode' .` returns nothing in committed code; OK in research docs since those are personal references).

### Hook-induced-hallucination test (CP17)
- [ ] Run the test (`docs/HOOK-INDUCED-HALLUCINATION-TEST.md`) against a fresh Claude Code session.
- [ ] Verify: when stop-validator fires, Claude pivots cleanly (rewrites with proof) instead of looping or apologizing.
- [ ] If Claude loops, this is a launch blocker. Tighten the block message.

### Demo and distribution prep
- [ ] Hero GIF (`discipline.gif`) optimized < 200KB. Verify GitHub renders it inline.
- [ ] At least one independent install. Ask someone who is not the author to run `./install.sh` on their own machine and report TTFV in seconds.
- [ ] Draft the launch post (Show HN title + one-paragraph body). Save in `docs/launch-post.md` (gitignored).
- [ ] Draft the X/LinkedIn thread. Save same place.
- [ ] Identify 3 to 5 people in the target audience (Claude Code power users) who get a private heads-up 24 hours before the public post.

---

## T minus 1 day: dry-run

- [ ] Re-render hero GIFs. Stale GIFs are the most common silent regression.
- [ ] Re-run `./install.sh && ./uninstall.sh` on a fresh test HOME.
- [ ] Push final commit. Wait for CI green.
- [ ] Set the GitHub repo to public if it was private.
- [ ] Add topics (see [GITHUB-TOPICS.md](GITHUB-TOPICS.md)).
- [ ] Pin the README on the repo profile.
- [ ] Send DM heads-up to the 3 to 5 advance audience members. Ask for honest feedback, no posts.

---

## T-zero: launch day

Suggested: **Tuesday, 8:00 AM Pacific.** HN front-page math favors Tue-Thu mornings. Avoid Mondays (catch-up) and Fridays (weekend dropoff).

### Sequence (90 minutes)

| Time | Action |
|------|--------|
| 08:00 PT | Post to Show HN. Title: "Show HN: god-mode-os, hooks that make Claude Code stop lying about 'done'." Body: 4 walls + install command + hero GIF link. |
| 08:05 | Post to r/ClaudeAI. Same title and body, formatted for Reddit. |
| 08:10 | X post: thread of 3 tweets. Tweet 1: hook + GIF. Tweet 2: 4 walls. Tweet 3: install line + repo link. |
| 08:15 | LinkedIn post: longform version (300 words), same wedge, less casual tone. |
| 08:30 | Comment on the Show HN post yourself with one extra technical detail (link to TIERS.md or the stress-test numbers). This is allowed and signals depth. |
| 08:45 | Reply to first 5 HN comments. Be technical. No marketing. |
| 09:30 | Check rank. If under HN front page top 30 by 09:30, you have a shot. If not, the post will not break out today. |

### What to NOT do on launch day

- Don't ask friends to upvote. HN flags this and shadowbans.
- Don't use marketing copy in comments. "Excited to share" kills credibility instantly.
- Don't argue with critics. Respond once with substance, then drop it.
- Don't ship a follow-up commit during launch. New commits on a launching repo signal instability. Ship fixes after the launch wave.

---

## T plus 24 hours

- [ ] Read every comment on HN, Reddit, X, LinkedIn. Triage: legitimate question, feature request, hostile, off-topic.
- [ ] Reply to legitimate questions inline within 24 hours.
- [ ] File issues for every non-trivial feature request, even ones you won't build.
- [ ] If a real bug is reported: confirm, file an issue, fix, ship a v0.1.1 patch. Do NOT ship a v0.2 mid-launch wave.
- [ ] If installs are happening, send a polite "thanks for installing" DM to anyone who tweeted about it. Ask one specific question: "what would have made the install easier."

### Metrics to watch

- Stars (HN front page typically buys 200 to 800 in 24 hours)
- Issues opened (signal of real users, not just lurkers)
- Forks (the strongest signal of intent to actually use)
- HN comment threads with real engineering questions (not "another LangChain wrapper" dismissals)

---

## T plus 72 hours

- [ ] Write a launch retro: what worked, what didn't, where to focus v0.2.
- [ ] If under 200 stars: the wedge or the demo missed. Read the comments for the recurring objection. Fix it before the next attempt.
- [ ] If 200 to 1000 stars: in the realistic range. Maintain.
- [ ] If 1000+ stars: distribution worked. Be ready for the next wave (Newsletter pickups, podcast asks).

---

## T plus 1 week

Stop reading metrics. Back to Moracode + interviews. Issues will accumulate; triage weekly.

---

## A/B tests queued from research

Not for launch day. Queue these for v0.2 or a relaunch:

1. **Hero tagline**: "stop lying about done" (current) vs "verify before ship" vs "sudo for AI agents". Test on a fresh landing page or Twitter A/B, not by editing the live README.
2. **Skip framing in intelligence digest**: topic-based filtering vs sentiment-based filtering.
3. **Routing demo positive vs loss frame**: "0 tokens, 9000 saved" vs "Without this: 9000 burned. With it: 0."
4. **Install command above-the-fold position**: top of README vs after the 4 walls.

---

## Risks accepted

- **GIFs may not loop on mobile.** Documented edge case in GitHub community discussions. Worth a check via mobile after launch, not a blocker.
- **Shipping with 4 demo GIFs may overwhelm.** Mitigation: README only embeds 1 hero (discipline) above the fold; the other 3 live in TIERS.md.
- **Tier 2 has Docker dep.** Mitigation: not in default install. Linked from a separate file.
- **Anthropic could ship native skill routing in 6 months.** Discipline hooks are the durable wedge. Router is the impressive demo. Plan accordingly.

---

## Definition of done for the launch

- v0.1 tag pushed to GitHub
- One Show HN post submitted
- One Reddit post submitted
- One X thread posted
- One LinkedIn longform posted
- 24 hours of replies handled
- Retro written

If all 7 happened, the launch shipped, regardless of star count.
