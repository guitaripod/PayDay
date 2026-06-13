#!/usr/bin/env bash
# Validate Pay Day's generated Factur-X hybrid PDF against Mustangproject
# (which bundles veraPDF for PDF/A-3b + the official EN 16931 / ZUGFeRD
# Schematron). This is DESIGN.md spike #1 as a repeatable check.
#
# It runs the hosted `exportForValidation` test on a simulator, which writes the
# real embedded PDF, then validates it. Exit 0 only if PDF + XML are valid.

set -u
set -o pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
[ -f "$ROOT/.env.local" ] && { set -a; . "$ROOT/.env.local"; set +a; }

JAVA="${JAVA:-/opt/homebrew/opt/openjdk/bin/java}"
command -v "$JAVA" >/dev/null 2>&1 || JAVA="$(command -v java || true)"
[ -n "$JAVA" ] || { echo "❌ Java not found (brew install openjdk)"; exit 1; }

MUSTANG="${MUSTANG_JAR:-/tmp/mustang-cli.jar}"
if [ ! -f "$MUSTANG" ]; then
  echo "▸ downloading Mustangproject CLI"
  curl -sL -o "$MUSTANG" "https://github.com/ZUGFeRD/mustangproject/releases/download/core-2.16.1/Mustang-CLI-2.16.1.jar"
fi

DEST="${1:-platform=iOS Simulator,name=iPhone 17 Pro}"
echo "▸ exporting hybrid PDF via hosted test"
xcodegen generate >/dev/null 2>&1
PDF=$(xcodebuild -project PayDay.xcodeproj -scheme PayDay -destination "$DEST" \
  -configuration Debug CODE_SIGNING_ALLOWED=NO test 2>&1 \
  | grep -oE "FACTURX_PDF_PATH=.*" | head -1 | cut -d= -f2)

[ -n "$PDF" ] && [ -f "$PDF" ] || { echo "❌ export test did not produce a PDF"; exit 1; }
cp "$PDF" /tmp/payday-facturx.pdf

echo "▸ validating /tmp/payday-facturx.pdf"
RESULT=$("$JAVA" -jar "$MUSTANG" --action validate --source /tmp/payday-facturx.pdf 2>&1)
echo "$RESULT" | grep -E "Parsed PDF:" | tail -1

if echo "$RESULT" | grep -q "Parsed PDF:valid XML:valid"; then
  echo "✅ Factur-X PDF/A-3b + EN 16931 XML valid"
  exit 0
fi
echo "❌ validation failed:"
echo "$RESULT" | grep -E "errorMessage|status=\"invalid\"" | head -20
exit 1
