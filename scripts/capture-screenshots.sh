#!/usr/bin/env bash
# Capture the App Store screenshot set for every listing locale on a simulator.
#
# Drives the DEBUG-only PAYDAY_DEMO routes (dashboard, editor, preview,
# preview-ic, list) with the simulator's language switched per locale, and
# writes raw 1320×2868 captures to marketing/appstore/raw/<locale>/<screen>.png.
# PAYDAY_DEMO_COUNTRY pins the dashboard's e-invoicing card to the market each
# locale sells into. Frame the output with scripts/frame-screenshots.swift.
#
# Usage: scripts/capture-screenshots.sh [locale ...]   (default: every locale)
#   PAYDAY_SIM_NAME overrides the simulator (default "iPhone 17 Pro Max");
#   PAYDAY_SCREENS="dashboard list" limits the screens captured.

set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
set -a; . "$ROOT/.env.local"; set +a

SIM_NAME="${PAYDAY_SIM_NAME:-iPhone 17 Pro Max}"
BUNDLE_ID="${PAYDAY_BUNDLE_ID}"
OUT="$ROOT/marketing/appstore/raw"
SCREENS=(${PAYDAY_SCREENS:-preview editor dashboard preview-ic list})

ALL_LOCALES="en-US en-GB de-DE fr-FR nl-NL fi es-ES it pl pt-BR ja ko zh-Hans zh-Hant"

# Prints "<AppleLanguages entry> <AppleLocale region> <PAYDAY_DEMO_COUNTRY>" for a listing locale.
# The demo country pins the dashboard card to the market that locale sells into; CJK and
# English listings show Belgium, the mandate in force, since they serve no single market.
locale_settings() {
  case "$1" in
    en-US)   echo "en BE BE" ;;
    en-GB)   echo "en-GB IE IE" ;;
    de-DE)   echo "de DE DE" ;;
    fr-FR)   echo "fr FR FR" ;;
    nl-NL)   echo "nl BE BE" ;;
    fi)      echo "fi FI FI" ;;
    es-ES)   echo "es ES ES" ;;
    it)      echo "it IT IT" ;;
    pl)      echo "pl PL PL" ;;
    pt-BR)   echo "pt-BR PT PT" ;;
    ja)      echo "ja BE BE" ;;
    ko)      echo "ko BE BE" ;;
    zh-Hans) echo "zh-Hans BE BE" ;;
    zh-Hant) echo "zh-Hant BE BE" ;;
    *) echo "❌ unknown locale '$1'" >&2; exit 1 ;;
  esac
}

LOCALES="${*:-$ALL_LOCALES}"

UDID="$(xcrun simctl list devices available -j | /opt/homebrew/bin/python3 -c "
import json,sys
devs=[d for r in json.load(sys.stdin)['devices'].values() for d in r if d['name']=='$SIM_NAME']
print(devs[0]['udid'] if devs else '')")"
if [ -z "$UDID" ]; then echo "❌ no simulator named '$SIM_NAME'" >&2; exit 1; fi

APP="$(find "$HOME/Library/Developer/Xcode/DerivedData" -name 'PayDay.app' -path '*Debug-iphonesimulator*' -not -path '*Index.noindex*' -print 2>/dev/null | head -1)"
if [ -z "$APP" ]; then echo "❌ no Debug simulator build — run scripts/ios-build.sh first" >&2; exit 1; fi

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl ui "$UDID" appearance light
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 --operatorName ""

capture() {
  local locale="$1" screen="$2" lang="$3" region="$4"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch \
    --terminate-running-process \
    "$UDID" "$BUNDLE_ID" \
    -AppleLanguages "($lang)" -AppleLocale "${lang//-/_}_${region}" >/dev/null
  sleep 2.5
  xcrun simctl io "$UDID" screenshot --type png "$OUT/$locale/$screen.png" >/dev/null
}

for locale in $LOCALES; do
  read -r lang region country <<< "$(locale_settings "$locale")"
  mkdir -p "$OUT/$locale"
  xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl install "$UDID" "$APP"
  for screen in "${SCREENS[@]}"; do
    SIMCTL_CHILD_PAYDAY_DEMO="$screen" \
    SIMCTL_CHILD_PAYDAY_DEMO_COUNTRY="$country" \
      capture "$locale" "$screen" "$lang" "$region"
    echo "  ✓ $locale/$screen"
  done
done

/opt/homebrew/bin/python3 - "$OUT" <<'EOF'
import os,struct,sys
root=sys.argv[1]; bad=[]
for locale in sorted(os.listdir(root)):
    d=os.path.join(root,locale)
    if not os.path.isdir(d): continue
    for f in sorted(os.listdir(d)):
        with open(os.path.join(d,f),'rb') as fh:
            fh.seek(16); w,h=struct.unpack('>II',fh.read(8))
        if (w,h)!=(1320,2868): bad.append((locale,f,w,h))
if bad:
    print("❌ wrong size:",bad); sys.exit(1)
print("✅ all captures are 1320×2868")
EOF
