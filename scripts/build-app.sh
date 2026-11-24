#!/bin/bash
# Builds build/Cutter.app from the Swift package and signs it.
#
#   ./scripts/build-app.sh
#
# Needs only the Xcode Command Line Tools. Options, as environment variables:
#
#   CUTTER_SIGNING=adhoc     Skip the local signing certificate. macOS then asks for
#                            Accessibility access again after each build.
#   CUTTER_APP_DIR=<dir>     Put Cutter.app in <dir> instead of build/, for example to try a
#                            build while the copy in build/ is running.
#   CUTTER_BUNDLE_ID=<id>    Build a copy with another bundle identifier. It has settings
#                            and a launch-at-login state of its own, and no Accessibility
#                            access until you grant it, so it can run next to the real one.
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/signing.env

bundle_identifier="${CUTTER_BUNDLE_ID:-com.ericzakariasson.Cutter}"
app="${CUTTER_APP_DIR:-build}/Cutter.app"

swift build -c release --product Cutter
binary="$(swift build -c release --show-bin-path)/Cutter"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Support/Info.plist "$app/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$bundle_identifier" "$app/Contents/Info.plist"
cp Support/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp "$binary" "$app/Contents/MacOS/Cutter"

sign_adhoc() {
    codesign --force --sign - --identifier "$bundle_identifier" "$app"
    echo "warning: ad-hoc signed. Accessibility access must be granted again after every build." >&2
}

if [ "${CUTTER_SIGNING:-local}" = "adhoc" ]; then
    sign_adhoc
elif scripts/setup-signing.sh &&
    security unlock-keychain -p "$SIGNING_KEYCHAIN_PASSWORD" "$SIGNING_KEYCHAIN" &&
    HOME="$SIGNING_HOME" codesign --force --sign "$SIGNING_IDENTITY" \
        --identifier "$bundle_identifier" --timestamp=none "$app"; then
    :
else
    echo "warning: could not sign with \"$SIGNING_IDENTITY\"; falling back to ad-hoc signing." >&2
    sign_adhoc
fi

codesign --verify --strict "$app"

case "$app" in
    /*) app_path="$app" ;;
    *) app_path="$(pwd)/$app" ;;
esac

echo
echo "Built $app_path"
codesign --display --requirements - "$app" 2>/dev/null | sed 's/^designated => /Signature: /'
if pgrep -xq Cutter; then
    echo "Cutter is running. Quit it from its menu bar icon and open this build to use it."
fi
echo "Open it with: open \"$app_path\""
