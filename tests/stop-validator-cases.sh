#!/bin/bash
# stop-validator-cases.sh
# Proves the stop validator blocks what it should and lets honest replies through.
# Usage: bash tests/stop-validator-cases.sh [path-to-hook]
# Every case builds a small transcript in a throwaway home folder and runs the real hook on it.
# Pass means every case got the expected result. Exit 0 on pass, 1 on fail.

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="${1:-$HERE/../hooks/discipline/stop-validator.sh}"
export HOOK
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

python3 -I - <<'PY'
import json, os, shutil, stat, subprocess, sys, tempfile

hook = os.environ["HOOK"]
home = os.path.realpath(tempfile.mkdtemp(prefix="stop-cases-"))

# A stand-in for the local model that always answers "1" (contradiction).
fake_model = os.path.join(home, "fake-ollama")
open(fake_model, "w").write("#!/bin/bash\ncat >/dev/null\necho 1\n")
os.chmod(fake_model, os.stat(fake_model).st_mode | stat.S_IEXEC)


def user(text):
    return {"message": {"role": "user", "content": text}}

def said(text):
    return {"message": {"role": "assistant", "content": [{"type": "text", "text": text}]}}

def used(tool, **inp):
    return {"message": {"role": "assistant", "content": [{"type": "tool_use", "name": tool, "input": inp}]}}

def result(text):
    return {"message": {"role": "user", "content": [{"type": "tool_result", "content": text}]}}

filler = [said("step %d of the work, nothing to see here" % i) for i in range(60)]
long_reply = ("The parser now reads the header first and then the rows. " * 8).strip()

# (id, expected, what it is, transcript lines, extra env)
CASES = [
 ("f01", "block", "claims about a file nobody opened",
  [user("fix the login bug"), said("I fixed the bug in src/auth/login.ts and it works now.")], {}),
 ("f02", "pass", "file was read with the Read tool just before",
  [user("fix the login bug"), used("Read", file_path="/repo/src/auth/login.ts"),
   said("I fixed the bug in src/auth/login.ts and it works now.")], {}),
 ("f03", "pass", "file was read long ago in the same chat (more than 30 lines back)",
  [user("fix the login bug"), used("Read", file_path="/repo/src/auth/login.ts")] + filler +
  [said("The bug was in src/auth/login.ts as found earlier.")], {}),
 ("f04", "pass", "the user typed the path themselves",
  [user("please look at src/auth/login.ts when you can"), said("Noted: src/auth/login.ts is next on the list.")], {}),
 ("f05", "pass", "a web address that looks like a path is not a file claim",
  [user("where are the docs"), said("The hooks guide is at https://example.com/docs/en/hooks.md for reference.")], {}),
 ("f06", "pass", "a path inside double quotes is an example, not a claim",
  [user("how do I name it"), said('Name it something like "config/app.yaml" and keep it short.')], {}),
 ("f07", "pass", "a path with three dots is a placeholder",
  [user("where do retros go"), said("They go to docs/retros/.../topic.md by default.")], {}),
 ("f08", "block", "an earlier block message cannot whitelist its own path",
  [user("fix the login bug"),
   user("Stop hook feedback: You made a claim about src/auth/login.ts without reading it first."),
   said("I fixed the bug in src/auth/login.ts and it works now.")], {}),
 ("f09", "pass", "file was touched by a Bash command",
  [user("run the tests"), used("Bash", command="pytest tests/test_login.py -q"),
   said("Ran tests/test_login.py and all 4 cases passed.")], {}),
 ("e01", "block", "an em dash in the reply",
  [user("status"), said("It works " + chr(8212) + " mostly.")], {}),
 ("e02", "pass", "a colon is not an em dash",
  [user("status"), said("Status: it works.")], {}),
 ("c01", "block", "a percentage with no source and no tool output",
  [user("is it faster"), said("Yes, it is about 40% faster than before.")], {}),
 ("c02", "pass", "a percentage that comes from tool output in this turn",
  [user("is it faster"), used("Bash", command="hyperfine ./run"), result("mean 1.2 s, 40% faster than baseline"),
   said("Yes, it is about 40% faster than before.")], {}),
 ("c03", "block", "tool output with a number from an EARLIER turn does not count",
  [user("time it"), used("Bash", command="hyperfine ./run"), result("mean 1.2 s"), said("Timed."),
   user("and how common is this bug"), said("Studies show 70% of teams hit it.")], {}),
 ("s01", "block", "a marketing filler word",
  [user("describe it"), said("This lets you leverage the cache across every request that the service handles in production today.")], {}),
 ("s02", "pass", "robust and scalable are ordinary technical words",
  [user("describe it"), said("The retry loop is robust against timeouts and the queue is scalable to many workers in production.")], {}),
 ("v01", "block", "says the tests pass, but only edited a file in this turn",
  [user("fix the add bug"), used("Edit", file_path="/repo/calc/add.py"), said("Fixed the sign error. All tests pass.")], {"GMOS_CHECK_VERIFY_CLAIM": "1"}),
 ("v02", "pass", "says the tests pass after running them in this turn",
  [user("fix the add bug"), used("Edit", file_path="/repo/calc/add.py"), used("Bash", command="pytest -q"),
   result("4 passed"), said("Fixed the sign error. All tests pass.")], {"GMOS_CHECK_VERIFY_CLAIM": "1"}),
 ("v03", "pass", "says plainly that the tests were not run",
  [user("fix the add bug"), used("Edit", file_path="/repo/calc/add.py"), said("Fixed the sign error. I have not run the tests.")], {"GMOS_CHECK_VERIFY_CLAIM": "1"}),
 ("v04", "pass", "a hedge is not a claim",
  [user("fix the add bug"), used("Edit", file_path="/repo/calc/add.py"), said("Fixed the sign error. The tests should pass now, please run them.")], {"GMOS_CHECK_VERIFY_CLAIM": "1"}),
 ("v05", "block", "a command from an EARLIER turn does not back a new claim",
  [user("run the tests"), used("Bash", command="pytest -q"), result("1 failed"), said("One case fails."),
   user("fix it"), used("Edit", file_path="/repo/calc/add.py"), said("Fixed. The build succeeds and the test suite is green.")], {"GMOS_CHECK_VERIFY_CLAIM": "1"}),
 ("v06", "pass", "the user said it first, the reply only repeats it",
  [user("the tests pass on my machine, what is next"), said("Good. Since the tests pass, the next step is the changelog.")], {"GMOS_CHECK_VERIFY_CLAIM": "1"}),
 ("v07", "block", "says it ran something with no command in this turn",
  [user("is it ok"), said("I ran the full suite and everything looks fine.")], {"GMOS_CHECK_VERIFY_CLAIM": "1"}),
 ("v08", "pass", "the check is off until switched on",
  [user("fix the add bug"), used("Edit", file_path="/repo/calc/add.py"), said("Fixed the sign error. All tests pass.")],
  {}),
 ("v09", "pass", "a question about the tests is not a claim",
  [user("fix the add bug"), used("Edit", file_path="/repo/calc/add.py"), said("Fixed the sign error. Do the tests pass on your side?")], {"GMOS_CHECK_VERIFY_CLAIM": "1"}),
 ("v10", "pass", "a helper agent did the run in this turn",
  [user("fix the add bug"), used("Agent", prompt="run the tests"), result("4 passed"), said("Fixed. All tests pass.")], {"GMOS_CHECK_VERIFY_CLAIM": "1"}),
 ("v11", "pass", "talking about an earlier run, named as such",
  [user("run the tests"), used("Bash", command="pytest -q"), result("4 passed"), said("All 4 pass."),
   user("still fine"), said("Yes. The tests passed earlier and nothing has changed since.")], {"GMOS_CHECK_VERIFY_CLAIM": "1"}),
 ("v12", "pass", "the build passes a flag: a verb with an object is not a claim",
  [user("add the flag"), used("Edit", file_path="/repo/ci.yml"), said("I updated the workflow so the build passes the --release flag to cargo.")], {"GMOS_CHECK_VERIFY_CLAIM": "1"}),
 ("v13", "pass", "describing what a test does is not a claim",
  [user("how do the tests avoid the network"), said("The tests pass a mock client into the constructor, so no network is used.")], {"GMOS_CHECK_VERIFY_CLAIM": "1"}),
 ("v14", "pass", "I ran into a problem is not a claim",
  [user("import it"), used("Edit", file_path="/repo/a.py"), said("I ran into a problem: the importer expects a header row that this file lacks.")], {"GMOS_CHECK_VERIFY_CLAIM": "1"}),
 ("v15", "pass", "saying nothing was tested is honest",
  [user("fix it"), used("Edit", file_path="/repo/a.py"), said("The fix is in. I tested nothing here.")], {"GMOS_CHECK_VERIFY_CLAIM": "1"}),
 ("v16", "pass", "a new test that passes an empty list",
  [user("add a test"), used("Edit", file_path="/repo/tests/test_total.py"), said("Added the case. The new test passes an empty list and expects 0.")], {"GMOS_CHECK_VERIFY_CLAIM": "1"}),
 ("v17", "pass", "a plan that names a later step",
  [user("plan it"), said("Plan: fix the parser, add a regression case, then confirm the tests pass.")], {"GMOS_CHECK_VERIFY_CLAIM": "1"}),
 ("c04", "block", "Studies show with a capital letter is still an unsourced claim",
  [user("how common is this bug"), said("Studies show most teams hit it sooner or later.")], {}),
 ("m01", "block", "the final reply is not in the transcript yet, only in the hook input",
  [user("is it faster")], {"_LAST": "Yes, it is about 40% faster than before."}),
 ("m02", "pass", "the hook input holds the final reply, an older reply in the transcript is not re-judged",
  [user("is it faster"), said("Yes, it is about 40% faster than before."), user("Stop hook feedback: no source")],
  {"_LAST": "It is faster, but I have no measurement to give you."}),
 ("k01", "pass", "the local contradiction check only records, it never stops the reply",
  [user("explain the parser"), said(long_reply), user("and now"), said(long_reply + " So the rows are read first.")],
  {"GMOS_OLLAMA": fake_model, "GMOS_CHECK_DODGE": "0"}),
]

failed = 0
for cid, expected, what, lines, extra in CASES:
    tpath = os.path.join(home, cid + ".jsonl")
    with open(tpath, "w") as fh:
        for l in lines:
            fh.write(json.dumps(l) + "\n")
    env = dict(os.environ)
    env["HOME"] = home
    for k in list(env):
        if k.startswith("GMOS_"):
            env.pop(k)
    env["GMOS_OLLAMA"] = os.path.join(home, "no-such-model")
    extra = dict(extra)
    last = extra.pop("_LAST", None)
    env.update(extra)
    inp = {"transcript_path": tpath, "stop_hook_active": False}
    if last is not None:
        inp["last_assistant_message"] = last
    inp = json.dumps(inp)
    try:
        p = subprocess.run(["bash", hook], input=inp, capture_output=True, text=True, env=env, timeout=60)
        got = "block" if p.returncode == 2 else ("pass" if p.returncode == 0 else "error-%d" % p.returncode)
    except subprocess.TimeoutExpired:
        got = "timeout"
    ok = got == expected
    failed += 0 if ok else 1
    print("%s  %s  expected %-5s got %-8s %s" % ("OK  " if ok else "FAIL", cid, expected, got, what))
    if not ok and p.stderr.strip():
        print("        hook said: " + p.stderr.strip().split("\n")[0][:160])

# The contradiction hit must be written down, with the earlier text beside it.
log = os.path.join(home, ".god-mode-os", "stop-validator.log")
logged = os.path.exists(log) and "LOG-ONLY" in open(log).read()
print("%s  k02  the contradiction hit is recorded in %s" % ("OK  " if logged else "FAIL", "~/.god-mode-os/stop-validator.log"))
failed += 0 if logged else 1

shutil.rmtree(home, ignore_errors=True)
print("TOTAL: %d cases. Failed: %d." % (len(CASES) + 1, failed))
sys.exit(0 if failed == 0 else 1)
PY
