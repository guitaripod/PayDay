#!/usr/bin/env bash
# Drives the Recommand Peppol adapter against the live PLAYGROUND (simulated AS4,
# zero cost, no real network). Loads the four Recommand vars from workers/.dev.vars
# and runs the gated live smoke test. Safe to re-run.
#
#   workers/.dev.vars must contain:
#     PEPPOL_PROVIDER=recommand
#     PEPPOL_GATEWAY_BASE=https://app.recommand.eu
#     PEPPOL_API_KEY=<playground api key>
#     PEPPOL_API_SECRET=<playground api secret>
#     PEPPOL_LEGAL_ENTITY_ID=<playground sending companyId>
#   Optional recipient override (defaults to a BE test participant):
#     PEPPOL_TEST_SCHEME / PEPPOL_TEST_ENDPOINT
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/workers/.dev.vars"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "✗ $ENV_FILE not found. Create it from workers/.dev.vars.example with the playground creds." >&2
  exit 1
fi

getvar() { grep -E "^$1=" "$ENV_FILE" | head -1 | cut -d= -f2- | sed 's/^"//; s/"$//'; }

export PEPPOL_GATEWAY_BASE="$(getvar PEPPOL_GATEWAY_BASE)"
export PEPPOL_API_KEY="$(getvar PEPPOL_API_KEY)"
export PEPPOL_API_SECRET="$(getvar PEPPOL_API_SECRET)"
export PEPPOL_LEGAL_ENTITY_ID="$(getvar PEPPOL_LEGAL_ENTITY_ID)"

missing=()
[[ -z "$PEPPOL_GATEWAY_BASE" ]] && missing+=(PEPPOL_GATEWAY_BASE)
[[ -z "$PEPPOL_API_KEY" ]] && missing+=(PEPPOL_API_KEY)
[[ -z "$PEPPOL_API_SECRET" ]] && missing+=(PEPPOL_API_SECRET)
[[ -z "$PEPPOL_LEGAL_ENTITY_ID" ]] && missing+=(PEPPOL_LEGAL_ENTITY_ID)
if (( ${#missing[@]} )); then
  echo "✗ Missing in $ENV_FILE: ${missing[*]}" >&2
  echo "  Add the playground API key (PEPPOL_API_KEY), secret (PEPPOL_API_SECRET)," >&2
  echo "  and sending companyId (PEPPOL_LEGAL_ENTITY_ID)." >&2
  exit 1
fi

echo "▸ Recommand playground: $PEPPOL_GATEWAY_BASE  company=$PEPPOL_LEGAL_ENTITY_ID"
export PEPPOL_LIVE_SMOKE=1
cd "$ROOT/workers"
npx vitest run peppol.live --reporter=verbose
