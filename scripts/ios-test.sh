#!/usr/bin/env bash
# Run Pay Day's test suites.
#
# 1. PayDayKit (SPM) — platform-agnostic, runs anywhere via `swift test`.
# 2. Hosted iOS unit tests (PayDayTests) on a simulator via xcodebuild.

set -u
set -o pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

# Source .env.local so xcodegen resolves ${PAYDAY_BUNDLE_ID}/${PAYDAY_TEAM_ID};
# an empty PRODUCT_BUNDLE_IDENTIFIER yields a bundle with no CFBundleIdentifier,
# which the simulator refuses to install ("Missing bundle ID").
if [ -f "$ROOT/.env.local" ]; then
  set -a; . "$ROOT/.env.local"; set +a
fi

echo "▸ swift test (PayDayKit)"
swift test
kit_status=$?
if [ $kit_status -ne 0 ]; then
  echo "❌ PayDayKit tests failed (exit $kit_status)." >&2
  exit $kit_status
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "·  xcodegen not installed — skipping hosted iOS tests."
  echo "✅ PayDayKit tests passed."
  exit 0
fi

echo "▸ xcodegen generate"
xcodegen generate >/dev/null

DEST="${1:-platform=iOS Simulator,name=iPhone 16}"
LOG=/tmp/payday-test.log
echo "▸ xcodebuild test ($DEST)"
xcodebuild \
  -project PayDay.xcodeproj \
  -scheme PayDay \
  -destination "$DEST" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  test \
  > "$LOG" 2>&1
status=$?

if command -v xcbeautify >/dev/null 2>&1; then
  xcbeautify --quieter < "$LOG" || true
fi

if [ $status -ne 0 ]; then
  echo "❌ Hosted iOS tests failed (exit $status):" >&2
  grep -nE "error:|failed|FAILED" "$LOG" | head -40 >&2
  exit $status
fi

echo "✅ All tests passed."
