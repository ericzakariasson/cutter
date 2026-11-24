#!/bin/bash
# Builds build/Cutter.app from the Swift package and signs it.
#
#   ./scripts/build-app.sh
#
# Needs only the Xcode Command Line Tools. Set CUTTER_SIGNING=adhoc to skip the local
# signing certificate; macOS will then ask for Accessibility access again after each build.
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/signing.env

bundle_identifier="com.ericzakariasson.Cutter"
app="build/Cutter.app"

swift build -c release --product Cutter
binary="$(swift build -c release --show-bin-path)/Cutter"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Support/Info.plist "$app/Contents/Info.plist"
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

echo
echo "Built $(pwd)/$app"
codesign --display --requirements - "$app" 2>/dev/null | sed 's/^designated => /Signature: /'
if pgrep -xq Cutter; then
    echo "Cutter is running. Quit it from its menu bar icon and open this build to use it."
fi
echo "Open it with: open \"$(pwd)/$app\""
