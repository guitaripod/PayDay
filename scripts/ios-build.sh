#!/usr/bin/env bash
# Build the Pay Day iOS app with full verification.
#
# - Regenerates PayDay.xcodeproj from project.yml (xcodegen) so newly added
#   source files are always picked up.
# - Captures xcodebuild's true exit code via `set -o pipefail`.
# - On failure, surfaces the first error / Swift 6 concurrency lines.
# - After a successful build, asserts that no .swift under PayDay/ or Sources/
#   is newer than the built binary. If anything is, the build was stale → abort.
#
# Usage: scripts/ios-build.sh [destination]
#   Default destination: a generic iOS Simulator (runs without a device).
#   Pass a device destination ("platform=iOS,id=<UDID>") to build for hardware.

set -u
set -o pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

if [ ! -f "$ROOT/.env.local" ]; then
  echo "❌ Missing .env.local — run scripts/setup.sh first." >&2
  exit 1
fi
set -a; . "$ROOT/.env.local"; set +a

if [ -z "${PAYDAY_TEAM_ID:-}" ] || [ -z "${PAYDAY_BUNDLE_ID:-}" ]; then
  echo "❌ .env.local missing PAYDAY_TEAM_ID or PAYDAY_BUNDLE_ID. Re-run scripts/setup.sh." >&2
  exit 1
fi

if [ ! -f "$ROOT/PayDay/Secrets.swift" ]; then
  echo "❌ PayDay/Secrets.swift missing — run scripts/setup.sh." >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "❌ xcodegen not installed (brew install xcodegen)." >&2
  exit 1
fi

DESTINATION="${1:-generic/platform=iOS Simulator}"
case "$DESTINATION" in
  *"Simulator"*) SDK_DIR="Debug-iphonesimulator" ;;
  *)             SDK_DIR="Debug-iphoneos" ;;
esac
LOG=/tmp/payday-build.log

echo "▸ xcodegen generate"
xcodegen generate >/dev/null

echo "▸ xcodebuild ($DESTINATION)"
xcodebuild \
  -project PayDay.xcodeproj \
  -scheme PayDay \
  -destination "$DESTINATION" \
  -configuration Debug \
  -allowProvisioningUpdates \
  -skipMacroValidation \
  build \
  > "$LOG" 2>&1
status=$?

if command -v xcbeautify >/dev/null 2>&1; then
  xcbeautify --quieter < "$LOG" || true
fi

if [ $status -ne 0 ]; then
  echo "" >&2
  echo "❌ BUILD FAILED (exit $status). First errors / concurrency complaints:" >&2
  grep -nE "error:|actor-isolated|nonisolated|Sendable|FAILED|Cannot find" "$LOG" | head -40 >&2
  exit $status
fi

DERIVED="$HOME/Library/Developer/Xcode/DerivedData"
APP="$(find "$DERIVED" -name 'PayDay.app' -path "*$SDK_DIR*" -not -path '*Index.noindex*' -print 2>/dev/null | head -1)"
if [ -z "$APP" ]; then
  echo "❌ Could not locate built PayDay.app in $DERIVED/*/Build/Products/$SDK_DIR" >&2
  exit 1
fi
BIN="$APP/PayDay"
if [ ! -f "$BIN" ]; then
  echo "❌ Binary missing inside $APP" >&2
  exit 1
fi

NEWER="$(find PayDay Sources -name '*.swift' -newer "$BIN" 2>/dev/null || true)"
if [ -n "$NEWER" ]; then
  echo "" >&2
  echo "❌ BUILD IS STALE — source files newer than the binary:" >&2
  echo "$NEWER" | sed 's/^/   /' >&2
  echo "" >&2
  echo "   Re-run scripts/ios-build.sh until this list is empty." >&2
  exit 1
fi

echo "✅ Build OK · $(stat -f '%z bytes · %Sm' "$BIN" 2>/dev/null || stat -c '%s bytes · %y' "$BIN")"
echo "$APP"
