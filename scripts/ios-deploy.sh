#!/usr/bin/env bash
# Build, install, and relaunch Pay Day on the configured physical device.
#
# Reads PAYDAY_DEVICE_UDID from .env.local. Uses xcrun devicectl (iOS 17+).

set -u
set -o pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

if [ ! -f "$ROOT/.env.local" ]; then
  echo "❌ Missing .env.local — run scripts/setup.sh first." >&2
  exit 1
fi
set -a; . "$ROOT/.env.local"; set +a

if [ -z "${PAYDAY_DEVICE_UDID:-}" ]; then
  echo "❌ PAYDAY_DEVICE_UDID not set in .env.local." >&2
  exit 1
fi

APP="$(scripts/ios-build.sh "platform=iOS,id=$PAYDAY_DEVICE_UDID" | tail -1)"
if [ ! -d "$APP" ]; then
  echo "❌ Build did not produce an app bundle." >&2
  exit 1
fi

echo "▸ install $APP"
xcrun devicectl device install app --device "$PAYDAY_DEVICE_UDID" "$APP"

BUNDLE_ID="${PAYDAY_BUNDLE_ID}"
echo "▸ launch $BUNDLE_ID"
xcrun devicectl device process launch --terminate-existing --device "$PAYDAY_DEVICE_UDID" "$BUNDLE_ID"

echo "✅ Deployed to ${PAYDAY_DEVICE_NAME:-$PAYDAY_DEVICE_UDID}"
