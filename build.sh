#!/bin/bash
# Build dictat from source and assemble a signed Dictat.app.
# Everything runs locally; the only network use is SwiftPM fetching FluidAudio
# and (on first launch of the app) the one-time Parakeet model download.

# Ensure we're running under bash even if invoked as `sh build.sh` (the shebang
# is ignored then), since this script uses bashisms like `set -o pipefail`.
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi

set -euo pipefail

cd "$(dirname "$0")"

# --dev : fast iteration loop. Builds debug (much faster than release), then kills the
#         running instance, relaunches the fresh build, and opens the Accessibility pane
#         so re-granting after the ad-hoc signature change is a single toggle. Ad-hoc can't
#         keep the grant across rebuilds (codesign needs a *trusted* cert for that, which we
#         deliberately dropped), so --dev just makes the unavoidable re-grant painless.
DEV=0
for arg in "$@"; do
    case "$arg" in
        --dev) DEV=1 ;;
        *) echo "unknown flag: $arg (supported: --dev)"; exit 2 ;;
    esac
done

BIN_NAME="dictat"
BUNDLE_ID="dev.local.dictat"
# Install straight into /Applications so Raycast, Spotlight and Launchpad all index it.
# (Single canonical copy — no stray duplicate left in the build folder.)
APP="/Applications/Dictat.app"

if [ "$DEV" -eq 1 ]; then
    CONFIG="debug"
    echo "==> [dev] Building debug binary (fast)"
else
    CONFIG="release"
    echo "==> Building release binary"
fi
swift build -c "$CONFIG"
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/${BIN_NAME}"

echo "==> Assembling ${APP}"
rm -rf "${APP}" ./Dictat.app   # drop any legacy copy left in the repo dir
mkdir -p "${APP}/Contents/MacOS"
mkdir -p "${APP}/Contents/Resources"
cp "${BIN_PATH}" "${APP}/Contents/MacOS/${BIN_NAME}"

# App icon (the mascot) — shows in Finder / Get Info / the Settings window.
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"
fi

cat > "${APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>          <string>${BIN_NAME}</string>
    <key>CFBundleIdentifier</key>          <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>                <string>dictat</string>
    <key>CFBundleDisplayName</key>         <string>dictat</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>CFBundleIconFile</key>            <string>AppIcon</string>
    <key>CFBundleIconName</key>            <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>  <string>0.1.0</string>
    <key>CFBundleVersion</key>             <string>1</string>
    <key>LSMinimumSystemVersion</key>      <string>14.0</string>
    <key>LSUIElement</key>                 <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>dictat records your voice and transcribes it on-device. Audio never leaves your Mac.</string>
</dict>
</plist>
PLIST

# Ad-hoc code signing. The signature changes on every build, so macOS treats each rebuild
# as a new app and the previous Accessibility grant becomes a stale entry that silently
# shadows this binary (paste fails without error). So we reset the grant on every build —
# you re-grant Accessibility once per rebuild. That's the cost of ad-hoc; the app is small
# and finished, so in normal use you build once and the grant just stays.
echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "${APP}"
echo "==> Clearing stale Accessibility grant for ${BUNDLE_ID} (re-grant after launch)"
tccutil reset Accessibility "${BUNDLE_ID}" >/dev/null 2>&1 || true

echo "==> Done: ${APP}"

if [ "$DEV" -eq 1 ]; then
    # Restart the running instance so you're testing the build you just made.
    echo "==> [dev] Relaunching"
    pkill -x "${BIN_NAME}" 2>/dev/null || true
    sleep 0.3
    open "${APP}"
    # The ad-hoc signature just changed, so the grant was reset above. Pop the Accessibility
    # pane so re-toggling Dictat takes a couple of seconds instead of a menu hunt.
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null || true
    echo "    Re-grant: in the Accessibility pane, remove the old 'Dictat' (–) and toggle the new one on."
else
    echo "    Launch with:  open ${APP}"
    echo "    First launch downloads the Parakeet model (~500 MB) once, then it's fully offline."
    echo "    Grant Microphone + Accessibility when prompted (Accessibility = paste at cursor)."
fi
