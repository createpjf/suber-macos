#!/bin/bash
# scripts/pseudo-locale-test.sh
#
# Slice 8f: pseudo-locale layout sanity check.
#
# Launches Suber with Apple's accented-pseudolanguage (`en_XA`), which
# expands every string ~40% and wraps it in brackets. Strings that overflow
# their container are visually obvious — labels truncated, buttons clipped,
# banners taller than 56pt.
#
# This is a manual QA tool, not a CI assertion. Run it before v1.6 release
# and snapshot-compare 4 key surfaces: consent modal, changes window,
# Settings→Autopilot, calendar with pending-cancel tile.
#
# USAGE
#   ./scripts/pseudo-locale-test.sh              # launch with en_XA
#   ./scripts/pseudo-locale-test.sh zh-Hans      # launch with zh-Hans locale
#   ./scripts/pseudo-locale-test.sh en           # normal English (smoke test)
#
# Requires Suber.app to have been built at least once. Uses the Debug build
# by default; pass `release` as the second argument for the Release build.

set -euo pipefail

LOCALE="${1:-en_XA}"
CONFIGURATION="${2:-Debug}"
DERIVED_DATA="${DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData}"

# Find the Suber.app bundle in DerivedData. Prefer the most recent build
# (sort by modification time).
APP_PATH=$(find "$DERIVED_DATA" -name "Suber.app" -type d -path "*/$CONFIGURATION/*" 2>/dev/null \
    | head -1)

if [ -z "$APP_PATH" ]; then
    echo "ERROR: Could not find Suber.app in $DERIVED_DATA"
    echo "       Build the app once in Xcode first, then retry."
    exit 1
fi

echo "Launching $APP_PATH"
echo "  AppleLanguages: ($LOCALE)"
echo "  Configuration:  $CONFIGURATION"
echo ""
echo "What to check:"
echo "  1. Open Settings → Autopilot. Do toggle labels truncate?"
echo "  2. Flip Watch Apple Mail ON. Does the consent modal fit in 540pt?"
echo "  3. Trigger a change and open the Changes Window. Do decision rows wrap?"
echo "  4. Cal a pending-cancel sub. Does the 'Nd' countdown overflow the tile?"
echo ""
echo "When expanded en_XA copy overflows, the fix is usually"
echo "(a) shorter source copy or (b) an explicit max-width + fixedSize+vertical."
echo ""

# Launch via `open -a` with AppleLanguages override. NSLanguages persists
# for this single invocation only.
open -a "$APP_PATH" --args -AppleLanguages "($LOCALE)" -AppleLocale "$LOCALE"
