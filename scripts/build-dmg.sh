#!/bin/bash
#
# scripts/build-dmg.sh — build a notarized, Developer-ID-signed DMG for distribution
#
# v1.4.0+: replaces the v1.0.0 ad-hoc-only script. Now drives the full
# Apple distribution pipeline:
#
#   1. Read MARKETING_VERSION from project.yml (single source of truth)
#   2. Build Release with Developer ID Application + Automatic provisioning
#      (Xcode handles the iCloud KVS + app-groups profile automatically)
#   3. Verify hardened runtime + signature
#   4. Package into a DMG
#   5. Sign the DMG with Developer ID + secure timestamp
#   6. Submit to Apple notarytool (uses keychain profile suber-notary)
#   7. Wait for notarization (typically ~2-5 min)
#   8. Staple the notarization ticket onto the DMG
#   9. Verify the DMG passes spctl --assess as type install
#
# USAGE
#   ./scripts/build-dmg.sh                  # uses MARKETING_VERSION from project.yml
#   ./scripts/build-dmg.sh 1.6.0            # override version
#   ./scripts/build-dmg.sh --skip-notarize  # build + sign DMG only, skip Apple submit
#                                            (useful for local QA before final release)
#
# REQUIREMENTS
#   - Developer ID Application: Jinfeng Peng (M2XH53X5DB) cert in Login keychain
#   - notarytool keychain profile "suber-notary" configured:
#       xcrun notarytool store-credentials suber-notary \
#           --apple-id pjf525@live.com --team-id M2XH53X5DB --password <app-password>
#   - Xcode signed in to the Apple Developer account (for Automatic provisioning)

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

APP_NAME="Suber"
DEVELOPER_ID="Developer ID Application: Jinfeng Peng (M2XH53X5DB)"
TEAM_ID="M2XH53X5DB"
NOTARY_PROFILE="suber-notary"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

SKIP_NOTARIZE="false"
VERSION_OVERRIDE=""
for arg in "$@"; do
    case "$arg" in
        --skip-notarize)
            SKIP_NOTARIZE="true"
            ;;
        --help|-h)
            sed -n '2,30p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            VERSION_OVERRIDE="$arg"
            ;;
    esac
done

# Auto-detect version from project.yml unless overridden.
if [ -n "$VERSION_OVERRIDE" ]; then
    VERSION="$VERSION_OVERRIDE"
else
    VERSION=$(grep -E 'MARKETING_VERSION:' "${PROJECT_DIR}/project.yml" \
              | head -1 \
              | awk -F'"' '{print $2}')
    if [ -z "$VERSION" ]; then
        echo "ERROR: Could not auto-detect MARKETING_VERSION from project.yml" >&2
        echo "       Pass version explicitly: ./scripts/build-dmg.sh 1.6.0" >&2
        exit 1
    fi
fi

DMG_NAME="${APP_NAME}-${VERSION}"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
APP_PATH="${EXPORT_DIR}/${APP_NAME}.app"
EXPORT_OPTIONS="${PROJECT_DIR}/scripts/ExportOptions.plist"
DMG_DIR="${BUILD_DIR}/dmg"
OUTPUT_DMG="${PROJECT_DIR}/${DMG_NAME}.dmg"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Building ${APP_NAME} v${VERSION}"
echo "  Target:  ${OUTPUT_DMG}"
echo "  Notary:  $([ "$SKIP_NOTARIZE" = "true" ] && echo 'SKIPPED (--skip-notarize)' || echo 'enabled')"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ---------------------------------------------------------------------------
# 1. Pre-flight checks
# ---------------------------------------------------------------------------

# Verify the signing identity is available.
if ! security find-identity -v -p codesigning 2>/dev/null \
     | grep -q "Developer ID Application: Jinfeng Peng"; then
    echo "ERROR: Developer ID Application signing identity not found in keychain." >&2
    echo "       Open Keychain Access, verify the cert is in the Login keychain." >&2
    exit 1
fi

# Verify notarytool credentials (unless skipping).
if [ "$SKIP_NOTARIZE" != "true" ]; then
    if ! xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1; then
        echo "ERROR: notarytool keychain profile '${NOTARY_PROFILE}' not configured." >&2
        echo "       Run: xcrun notarytool store-credentials ${NOTARY_PROFILE} \\" >&2
        echo "                --apple-id <email> --team-id ${TEAM_ID} --password <app-pw>" >&2
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# 2. Clean
# ---------------------------------------------------------------------------

echo "[1/8] Cleaning previous build…"
rm -rf "${BUILD_DIR}"
rm -f "${OUTPUT_DMG}"

# ---------------------------------------------------------------------------
# 3. Build Release (Automatic signing handles iCloud + app-groups profile)
# ---------------------------------------------------------------------------

echo "[2/8] Archiving Release (Automatic provisioning, iCloud + app-groups + Apple Events)…"
xcodebuild archive \
    -project "${PROJECT_DIR}/Suber.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -archivePath "${ARCHIVE_PATH}" \
    -derivedDataPath "${BUILD_DIR}/DerivedData" \
    -destination 'platform=macOS' \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="${TEAM_ID}" \
    OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
    2>&1 | tail -8

if [ ! -d "${ARCHIVE_PATH}" ]; then
    echo "ERROR: Archive failed — ${ARCHIVE_PATH} not found" >&2
    exit 1
fi

echo "      Exporting Developer ID .app from archive…"
xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_DIR}" \
    -exportOptionsPlist "${EXPORT_OPTIONS}" \
    -allowProvisioningUpdates \
    2>&1 | tail -6

if [ ! -d "${APP_PATH}" ]; then
    echo "ERROR: Export failed — ${APP_PATH} not found" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 4. Verify the .app
# ---------------------------------------------------------------------------

echo "[3/8] Verifying signature + hardened runtime on .app…"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}" 2>&1 | tail -3

# Confirm the hardened runtime is enabled (notarization rejects builds without it).
# Format on Xcode 15+: `flags=0x10000(runtime)`. Write codesign output to a temp
# file first, then grep — the inline `codesign | grep -q` pipeline behaves
# inconsistently under `set -o pipefail` when codesign streams to stderr.
CS_OUT=$(mktemp)
codesign -d --verbose=2 "${APP_PATH}" >"${CS_OUT}" 2>&1 || true
if ! grep -q "(runtime)" "${CS_OUT}"; then
    echo "ERROR: hardened runtime NOT enabled. notarization will reject." >&2
    echo "       codesign output below for diagnosis:" >&2
    cat "${CS_OUT}" >&2
    rm -f "${CS_OUT}"
    exit 1
fi
rm -f "${CS_OUT}"

# ---------------------------------------------------------------------------
# 5. Build the DMG
# ---------------------------------------------------------------------------

echo "[4/8] Building DMG…"
mkdir -p "${DMG_DIR}"
cp -R "${APP_PATH}" "${DMG_DIR}/"
ln -s /Applications "${DMG_DIR}/Applications"

hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${DMG_DIR}" \
    -ov \
    -format UDZO \
    "${OUTPUT_DMG}" \
    2>&1 | tail -3

# ---------------------------------------------------------------------------
# 6. Sign the DMG (notarization requires the DMG itself to be signed)
# ---------------------------------------------------------------------------

echo "[5/8] Signing DMG with Developer ID + secure timestamp…"
codesign --sign "${DEVELOPER_ID}" --timestamp "${OUTPUT_DMG}"
codesign --verify --verbose=2 "${OUTPUT_DMG}" 2>&1 | tail -2

# ---------------------------------------------------------------------------
# 7. Notarize (Apple — typically 2-5 min)
# ---------------------------------------------------------------------------

if [ "$SKIP_NOTARIZE" = "true" ]; then
    echo "[6/8] Notarization SKIPPED (--skip-notarize)"
    echo "[7/8] Stapler SKIPPED (no notarization ticket)"
    echo "[8/8] spctl assess SKIPPED (Gatekeeper will reject unnotarized DMG)"
else
    echo "[6/8] Submitting to Apple notarytool (waits for ticket — usually 2-5 min)…"
    xcrun notarytool submit "${OUTPUT_DMG}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --wait \
        2>&1 | tee /tmp/notarize-${VERSION}.log

    if ! grep -q "status: Accepted" /tmp/notarize-${VERSION}.log; then
        echo "ERROR: notarization did NOT receive Accepted status." >&2
        echo "       Inspect /tmp/notarize-${VERSION}.log for the rejection reason." >&2
        SUB_ID=$(grep -E "^\s+id:" /tmp/notarize-${VERSION}.log | head -1 | awk '{print $2}')
        if [ -n "$SUB_ID" ]; then
            echo "       Submission ID: ${SUB_ID}" >&2
            echo "       Run: xcrun notarytool log ${SUB_ID} --keychain-profile ${NOTARY_PROFILE}" >&2
        fi
        exit 1
    fi

    # ----------------------------------------------------------------------
    # 8. Staple the notarization ticket so the DMG works offline
    # ----------------------------------------------------------------------

    echo "[7/8] Stapling notarization ticket…"
    xcrun stapler staple "${OUTPUT_DMG}"
    xcrun stapler validate "${OUTPUT_DMG}"

    # ----------------------------------------------------------------------
    # 9. Final Gatekeeper assessment
    # ----------------------------------------------------------------------

    echo "[8/9] spctl assess (Gatekeeper sanity check)…"
    spctl --assess --type install --verbose "${OUTPUT_DMG}" 2>&1 | tail -3

    # ----------------------------------------------------------------------
    # v1.8.0: Generate signed appcast.xml for Sparkle in-app updater.
    # Sparkle CLI tools live at ~/.local/sparkle/bin (downloaded from
    # https://github.com/sparkle-project/Sparkle/releases since the brew
    # cask is deprecated as of 2026-04). Private EdDSA key lives in macOS
    # Keychain — generate_appcast picks it up automatically.
    # ----------------------------------------------------------------------

    echo "[9/9] Generating signed appcast.xml for Sparkle…"
    SPARKLE_BIN="${HOME}/.local/sparkle/bin"
    if [ ! -x "${SPARKLE_BIN}/generate_appcast" ]; then
        echo "ERROR: ${SPARKLE_BIN}/generate_appcast not found." >&2
        echo "       Download Sparkle from https://github.com/sparkle-project/Sparkle/releases" >&2
        echo "       Extract Sparkle-X.Y.Z.tar.xz to ~/.local/sparkle/" >&2
        exit 1
    fi

    APPCAST_DIR="${BUILD_DIR}/appcast"
    mkdir -p "${APPCAST_DIR}"
    cp "${OUTPUT_DMG}" "${APPCAST_DIR}/"
    "${SPARKLE_BIN}/generate_appcast" \
        --download-url-prefix "https://github.com/createpjf/suber-macos/releases/download/v${VERSION}/" \
        "${APPCAST_DIR}" 2>&1 | tail -5

    APPCAST_OUT="${PROJECT_DIR}/appcast.xml"
    cp "${APPCAST_DIR}/appcast.xml" "${APPCAST_OUT}"
    echo "      appcast.xml → ${APPCAST_OUT}"
    echo ""
    echo "      Upload BOTH ${OUTPUT_DMG} AND ${APPCAST_OUT} to the GitHub release:"
    echo "      gh release create v${VERSION} ${OUTPUT_DMG} ${APPCAST_OUT} --notes-file …"
fi

# ---------------------------------------------------------------------------
# Cleanup intermediate build dir; keep the DMG (and appcast.xml at project root).
# ---------------------------------------------------------------------------

rm -rf "${BUILD_DIR}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Done: ${DMG_NAME}.dmg"
echo "  Path:    ${OUTPUT_DMG}"
echo "  Size:    $(du -h "${OUTPUT_DMG}" | cut -f1)"
if [ "$SKIP_NOTARIZE" = "true" ]; then
    echo "  Status:  signed only (NOT notarized)"
else
    echo "  Status:  signed, notarized, stapled"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
if [ "$SKIP_NOTARIZE" != "true" ]; then
    echo "Next: gh release create v${VERSION} ${OUTPUT_DMG} --notes-file CHANGELOG.md"
fi
