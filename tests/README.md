# Tests

Three case files run the real hooks against small made-up inputs in a throwaway home folder.
Nothing on your machine is touched. Each prints one line per case and exits 1 on any failure.

| File | What it proves | Cases |
|---|---|---|
| `install-guard-cases.sh` | Reading or naming a protected path passes; writing, moving or deleting one is blocked | 253 |
| `stop-validator-cases.sh` | Unbacked file and number claims are blocked, the opt-in "tests pass" check works; honest replies pass | 38 |
| `hooks-cases.sh` | session-retro, push-gate, dash-guard, folder rule and the plugin wiring behave as documented | 57 |

```bash
bash tests/install-guard-cases.sh
bash tests/stop-validator-cases.sh
bash tests/hooks-cases.sh
```

CI runs all three on Linux and macOS, next to `smoke.sh`, `shellcheck` and the install dry run.
