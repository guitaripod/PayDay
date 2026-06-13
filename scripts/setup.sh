#!/usr/bin/env bash
# One-time local setup for Pay Day.
#
# - Creates .env.local from .env.local.example if missing (auto-detecting the
#   signing Team ID when possible).
# - Copies PayDay/Secrets.example.swift -> PayDay/Secrets.swift if missing.
# - Regenerates PayDay.xcodeproj from project.yml (xcodegen).
# - Resolves the local PayDayKit package + GRDB + AICredits.
#
# Safe to re-run.

set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

echo "==> Pay Day setup"

if [ ! -f .env.local ]; then
  if [ ! -f .env.local.example ]; then
    echo "error: .env.local.example missing — cannot bootstrap .env.local" >&2
    exit 1
  fi
  echo "==> Creating .env.local from .env.local.example"
  TEAM_ID="$(security find-identity -v -p codesigning 2>/dev/null | grep -oE '\(([A-Z0-9]{10})\)' | head -1 | tr -d '()' || true)"
  if [ -n "$TEAM_ID" ]; then
    sed "s|^PAYDAY_TEAM_ID=.*$|PAYDAY_TEAM_ID=$TEAM_ID|" .env.local.example > .env.local
  else
    cp .env.local.example .env.local
  fi
  chmod 600 .env.local
  echo "    edit .env.local: set PAYDAY_TEAM_ID + device values"
else
  echo "·  .env.local already exists, leaving it"
fi

if [ ! -f PayDay/Secrets.swift ]; then
  echo "==> Creating PayDay/Secrets.swift from example"
  cp PayDay/Secrets.example.swift PayDay/Secrets.swift
  echo "    edit PayDay/Secrets.swift: workerBaseURL + revenueCatPublicKey"
else
  echo "·  PayDay/Secrets.swift already exists, leaving it"
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen not installed (brew install xcodegen)." >&2
  exit 1
fi

echo "==> xcodegen generate"
xcodegen generate

echo "==> swift package resolve"
swift package resolve >/dev/null 2>&1 || true

echo "==> Done. Next: edit .env.local + PayDay/Secrets.swift, then scripts/ios-build.sh"
