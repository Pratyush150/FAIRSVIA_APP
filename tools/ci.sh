#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Ride App local CI gate — the same checks GitHub Actions runs, but against the
# already-running Docker stack on this self-hosted box. Run before every commit:
#
#     ./tools/ci.sh            # full gate (backend unit+e2e, flutter analyze+test)
#     ./tools/ci.sh --fast     # skip e2e (quicker inner-loop feedback)
#
# Exit code is non-zero if ANY stage fails, so it doubles as a pre-push hook.
# ---------------------------------------------------------------------------
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PATH="$PATH:/home/nova-robotics/flutter/bin"

FAST=0
[ "${1:-}" = "--fast" ] && FAST=1

FAILED=()
pass() { printf "  \033[32m✓ %s\033[0m\n" "$1"; }
fail() { printf "  \033[31m✗ %s\033[0m\n" "$1"; FAILED+=("$1"); }
stage() { printf "\n\033[1m▶ %s\033[0m\n" "$1"; }

BACKEND_CTR=ubernav_backend

stage "Backend — type-check (nest build)"
if docker exec "$BACKEND_CTR" npm run build >/tmp/ci-be-build.log 2>&1; then
  pass "backend build"
else
  fail "backend build"; tail -20 /tmp/ci-be-build.log
fi

stage "Backend — unit tests (jest)"
if docker exec "$BACKEND_CTR" npx jest --ci --silent >/tmp/ci-be-unit.log 2>&1; then
  pass "$(grep -oE 'Tests:.*' /tmp/ci-be-unit.log | head -1)"
else
  fail "backend unit tests"; tail -25 /tmp/ci-be-unit.log
fi

if [ "$FAST" -eq 0 ]; then
  stage "Backend — e2e tests (jest, real Postgres+Redis)"
  if docker exec "$BACKEND_CTR" npm run test:e2e >/tmp/ci-be-e2e.log 2>&1; then
    pass "$(grep -oE 'Tests:.*' /tmp/ci-be-e2e.log | head -1)"
  else
    fail "backend e2e tests"; tail -25 /tmp/ci-be-e2e.log
  fi
fi

stage "Flutter — static analysis"
if flutter analyze >/tmp/ci-analyze.log 2>&1; then
  pass "flutter analyze (no issues)"
else
  fail "flutter analyze"; tail -30 /tmp/ci-analyze.log
fi

stage "Flutter — widget/bloc tests"
for d in packages/* apps/*; do
  # Only dirs that actually contain *_test.dart files (an empty test/ dir errors).
  compgen -G "$d/test/**/*_test.dart" >/dev/null 2>&1 || compgen -G "$d/test/*_test.dart" >/dev/null 2>&1 || continue
  name="$(basename "$d")"
  if (cd "$d" && flutter test --reporter compact) >/tmp/ci-ft.log 2>&1; then
    pass "test: $name"
  else
    fail "test: $name"; tail -20 /tmp/ci-ft.log
  fi
done

echo
if [ ${#FAILED[@]} -eq 0 ]; then
  printf "\033[42m\033[30m PASS \033[0m  All CI stages green.\n"
  exit 0
else
  printf "\033[41m\033[37m FAIL \033[0m  %d stage(s) failed: %s\n" "${#FAILED[@]}" "${FAILED[*]}"
  exit 1
fi
