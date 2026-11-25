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
#   CUTTER_DISTRIBUTION=1    Build the app the way it is given to other people: for Apple
#                            silicon and Intel Macs in one binary, without debug symbols
#                            (which carry this machine's paths), and failing rather than
#                            falling back to ad-hoc signing. scripts/make-dmg.sh sets this
#                            and signs a release itself, with the release key.
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/signing.env

bundle_identifier="${CUTTER_BUNDLE_ID:-com.ericzakariasson.Cutter}"
app="${CUTTER_APP_DIR:-build}/Cutter.app"
distribution="${CUTTER_DISTRIBUTION:-}"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Support/Info.plist "$app/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$bundle_identifier" "$app/Contents/Info.plist"
cp Support/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

if [ -n "$distribution" ]; then
    # A universal build in one step needs Xcode. With the Command Line Tools alone, each
    # architecture is built by itself, in a build folder of its own, and the two are joined.
    slices=()
    for arch in arm64 x86_64; do
        swift build -c release --product Cutter --arch "$arch" --build-path ".build/distribution-$arch"
        slices+=("$(swift build -c release --arch "$arch" --build-path ".build/distribution-$arch" --show-bin-path)/Cutter")
    done
    lipo -create "${slices[@]}" -output "$app/Contents/MacOS/Cutter"
    strip -S "$app/Contents/MacOS/Cutter"
else
    swift build -c release --product Cutter
    cp "$(swift build -c release --show-bin-path)/Cutter" "$app/Contents/MacOS/Cutter"
fi

sign_adhoc() {
    codesign --force --sign - --identifier "$bundle_identifier" "$app"
    if [ -z "$distribution" ]; then
        echo "warning: ad-hoc signed. Accessibility access must be granted again after every build." >&2
    fi
}

if [ "${CUTTER_SIGNING:-local}" = "adhoc" ]; then
    sign_adhoc
elif scripts/setup-signing.sh &&
    security unlock-keychain -p "$SIGNING_KEYCHAIN_PASSWORD" "$SIGNING_KEYCHAIN" &&
    HOME="$SIGNING_HOME" codesign --force --sign "$SIGNING_IDENTITY" \
        --identifier "$bundle_identifier" --timestamp=none "$app"; then
    :
elif [ -n "$distribution" ]; then
    echo "error: could not sign with \"$SIGNING_IDENTITY\"." >&2
    exit 1
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
if [ -z "$distribution" ]; then
    if pgrep -xq Cutter; then
        echo "Cutter is running. Quit it from its menu bar icon and open this build to use it."
    fi
    echo "Open it with: open \"$app_path\""
fi
