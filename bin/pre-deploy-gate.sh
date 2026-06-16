#!/bin/bash
# pre-deploy-gate.sh : fail-closed security gate. Run before ship/deploy.
# Gates: 1) secret scan (gitleaks, fully local)  2) dependency CVEs (osv-scanner, optional).
#
# Privacy: gitleaks runs entirely on your machine. osv-scanner queries the public OSV
# database (osv.dev) over the network to look up CVEs, so it only runs if you install it.
# Without osv-scanner the gate still works as a local-only secret scanner.
#
# Usage: pre-deploy-gate.sh [dir]   (default: current dir). Exit 0 = pass, 1 = fail.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
DIR="${1:-.}"
fail=0
echo "============================================"
echo " PRE-DEPLOY SECURITY GATE  ::  $DIR"
echo "============================================"

echo ""; echo "--- [1/2] Secret scan (gitleaks, local) ---"
if command -v gitleaks >/dev/null 2>&1; then
  if gitleaks detect --source "$DIR" --no-git --redact --no-banner 2>/dev/null; then
    echo "  OK: no secrets found"
  else
    echo "  FAIL: secrets detected, do not deploy"; fail=1
  fi
else echo "  skipped: gitleaks not installed (brew install gitleaks)"; fi

echo ""; echo "--- [2/2] Dependency CVEs (osv-scanner, optional, online) ---"
if command -v osv-scanner >/dev/null 2>&1; then
  out=$(osv-scanner scan --recursive "$DIR" 2>/dev/null)
  if echo "$out" | grep -qiE "GHSA-|CVE-[0-9]|vulnerabilit(y|ies) found"; then
    echo "$out" | tail -15; echo "  FAIL: vulnerable dependencies, review before deploy"; fail=1
  else echo "  OK: no known-vulnerable dependencies"; fi
else echo "  skipped: osv-scanner not installed (optional; it contacts osv.dev)"; fi

echo ""; echo "============================================"
if [ $fail -eq 0 ]; then echo " GATE PASSED"; else echo " GATE FAILED: fix the above before deploy"; fi
echo "============================================"
exit $fail
