### What this PR does

(One sentence.)

### Related issue

Fixes #

### Type

- [ ] Bug fix (does not change behavior for existing users)
- [ ] New check / hook (must default OFF)
- [ ] Docs / cosmetic
- [ ] Refactor (no behavior change, justification required)

### Pre-flight checklist

- [ ] `shellcheck` passes on all changed `.sh` files
- [ ] If new hook: kill switch (`$GMOS_KILL_SWITCH`) honored, admin override (`$GMOS_ADMIN_OVERRIDE=1`) honored
- [ ] If new mandatory dep: justified in description (Tier 1 limit is `jq` + `python3`)
- [ ] `./uninstall.sh` cleans up the new state

### How to verify

(Exact command(s) the reviewer should run.)
