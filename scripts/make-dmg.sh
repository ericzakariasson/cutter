#!/bin/bash
# Builds Cutter for other people and packages it as dist/Cutter-<version>.dmg: the app and
# a shortcut to the Applications folder, for dragging one onto the other.
#
#   ./scripts/make-dmg.sh
#
# Run it in a terminal: it asks for the release key's passphrase. The version comes from
# CFBundleShortVersionString in Support/Info.plist, the same place the app reads it from.
# Needs only the Xcode Command Line Tools. Nothing opens on screen: the image is filled
# and checked through mounts that Finder does not show. The DMG is not notarized by Apple.
#
# A release is signed with the release key (scripts/setup-release-key.sh makes it; see
# scripts/signing.env). People who gave an earlier release Accessibility access keep it
# only if the next one is signed with the same key, so the script stops when the key's
# certificate is not the one in Support/release-certificate.txt.
#
# A DMG signed any other way is for trying things out, and its name says so:
#
#   CUTTER_SIGNING=adhoc      No key. Writes Cutter-<version>-adhoc.dmg. Every update
#                             signed this way loses its Accessibility access.
#   CUTTER_SIGNING=local      The local build key, whose password is public (see
#                             scripts/signing.env). Writes Cutter-<version>-local-key.dmg.
#
#   CUTTER_RELEASE_KEY=new    Accept a release key that is not the one in
#                             Support/release-certificate.txt, when it really has changed.
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/signing.env

for tool in swift lipo strip codesign hdiutil plutil shasum security; do
    if ! command -v "$tool" >/dev/null; then
        echo "error: $tool is not installed." >&2
        exit 1
    fi
done

output=dist
app="$output/Cutter.app"
bundle_identifier="com.ericzakariasson.Cutter"
version="$(plutil -extract CFBundleShortVersionString raw Support/Info.plist)"
signing="${CUTTER_SIGNING:-release}"

# A run that stops halfway must not leave an earlier DMG behind to be mistaken for its result.
rm -f "$output"/Cutter-*.dmg

case "$signing" in
    release)
        dmg="$output/Cutter-$version.dmg"
        if [ ! -e "$RELEASE_SIGNING_KEYCHAIN" ]; then
            echo "error: there is no release key on this Mac ($RELEASE_SIGNING_DIR)." >&2
            echo "Create it once with ./scripts/setup-release-key.sh, or restore it from your backup." >&2
            echo "For a DMG to try out, not to publish, use CUTTER_SIGNING=adhoc." >&2
            exit 1
        fi
        ;;
    adhoc)
        dmg="$output/Cutter-$version-adhoc.dmg"
        ;;
    local)
        dmg="$output/Cutter-$version-local-key.dmg"
        ;;
    *)
        echo "error: CUTTER_SIGNING must be release, adhoc or local." >&2
        exit 1
        ;;
esac

work="$(mktemp -d)"
mount="$work/mount"
mkdir "$mount"
cleanup() {
    hdiutil detach "$mount" -quiet 2>/dev/null || true
    if [ "$signing" = "release" ]; then
        security lock-keychain "$RELEASE_SIGNING_KEYCHAIN" 2>/dev/null || true
    fi
    rm -rf "$work"
}
trap cleanup EXIT

# build-app.sh signs with the local key or with none. A release is signed again below.
if [ "$signing" = "local" ]; then
    CUTTER_DISTRIBUTION=1 CUTTER_APP_DIR="$output" CUTTER_BUNDLE_ID= CUTTER_SIGNING=local scripts/build-app.sh
else
    CUTTER_DISTRIBUTION=1 CUTTER_APP_DIR="$output" CUTTER_BUNDLE_ID= CUTTER_SIGNING=adhoc scripts/build-app.sh
fi

if [ "$signing" = "release" ]; then
    # The keychain is open only for the moment of signing.
    read_passphrase "Passphrase for the release key: "
    if ! security_unseen unlock-keychain -p "$passphrase" "$RELEASE_SIGNING_KEYCHAIN" 2>/dev/null; then
        echo "error: that passphrase does not unlock the release key." >&2
        exit 1
    fi
    HOME="$RELEASE_SIGNING_HOME" codesign --force --sign "$RELEASE_SIGNING_IDENTITY" \
        --identifier "$bundle_identifier" --timestamp=none "$app"
    security lock-keychain "$RELEASE_SIGNING_KEYCHAIN"
fi

# Which key signed the app. An ad-hoc signature names no certificate.
certificate="$(codesign --display --requirements - "$app" 2>/dev/null |
    sed -n 's/.*certificate leaf = H"\([0-9a-f]*\)".*/\1/p')"
release_certificate="$(grep -v '^#' Support/release-certificate.txt | tr -d '[:space:]' || true)"

case "$signing" in
    release)
        if [ -z "$certificate" ]; then
            echo "error: the app did not get signed with the release key." >&2
            exit 1
        elif [ -z "$release_certificate" ]; then
            echo "note: Support/release-certificate.txt names no certificate yet. Put $certificate in it." >&2
        elif [ "$certificate" != "$release_certificate" ]; then
            echo "This build is signed with certificate $certificate," >&2
            echo "but releases are signed with      $release_certificate (Support/release-certificate.txt)." >&2
            if [ "${CUTTER_RELEASE_KEY:-}" != "new" ]; then
                echo "error: not the release key. Everyone who installed an earlier release would have" >&2
                echo "to grant Accessibility access again. If the release key really has changed, run" >&2
                echo "again with CUTTER_RELEASE_KEY=new and update that file." >&2
                exit 1
            fi
            echo "Continuing because CUTTER_RELEASE_KEY=new. Put the first certificate in that file." >&2
        fi
        ;;
    adhoc)
        echo "warning: signed without a key. Do not publish $dmg: it is for trying things out." >&2
        ;;
    local)
        echo "warning: signed with the local build key, whose password is public." >&2
        echo "Do not publish $dmg: it is for trying things out." >&2
        if [ -n "$release_certificate" ] && [ "$certificate" = "$release_certificate" ]; then
            echo "error: Support/release-certificate.txt names the local build key as the release key." >&2
            exit 1
        fi
        ;;
esac

# Mounted where only this script looks, and hidden from Finder and the desktop.
attach() {
    hdiutil attach "$1" -quiet -nobrowse -noautoopen -mountpoint "$mount" "${@:2}"
}

# An empty image with room to spare, filled through a mount of its own. The shorter
# `hdiutil create -srcfolder` mounts the new volume where Finder shows it, and
# `hdiutil makehybrid` marks every file with Finder information, which breaks the app's
# signature check.
megabytes=$(( $(du -sm "$app" | cut -f 1) * 2 + 8 ))
hdiutil create -quiet -size "${megabytes}m" -fs HFS+ -volname Cutter -layout NONE "$work/Cutter.dmg"
attach "$work/Cutter.dmg"
cp -R "$app" "$mount/Cutter.app"
ln -s /Applications "$mount/Applications"
rm -rf "$mount/.fseventsd" "$mount/.Trashes"
hdiutil detach "$mount" -quiet

rm -f "$dmg"
hdiutil convert -quiet "$work/Cutter.dmg" -format UDZO -imagekey zlib-level=9 -o "$dmg"

# Check what someone who downloads the DMG gets.
hdiutil verify -quiet "$dmg"
attach "$dmg" -readonly
mounted="$mount/Cutter.app"

fail() {
    echo "error: $1" >&2
    exit 1
}
[ "$(ls -A "$mount" | sort | tr '\n' ' ')" = "Applications Cutter.app " ] ||
    fail "the DMG holds something other than Cutter.app and the Applications shortcut."
[ "$(readlink "$mount/Applications")" = "/Applications" ] || fail "the DMG has no shortcut to /Applications."
[ -z "$(xattr -lr "$mounted")" ] || fail "the app in the DMG carries extended attributes."
codesign --verify --deep --strict "$mounted" || fail "the app in the DMG fails its signature check."
[ "$(plutil -extract CFBundleShortVersionString raw "$mounted/Contents/Info.plist")" = "$version" ] ||
    fail "the app in the DMG is not version $version."
[ "$(lipo -archs "$mounted/Contents/MacOS/Cutter")" = "x86_64 arm64" ] ||
    fail "the app in the DMG is not built for both Intel and Apple silicon."
if grep -rqa -e "$HOME" -e "/Users/" "$mounted"; then
    fail "the app in the DMG contains a path from this machine."
fi
minimum_macos="$(plutil -extract LSMinimumSystemVersion raw "$mounted/Contents/Info.plist")"
hdiutil detach "$mount" -quiet

echo
echo "Wrote $dmg"
echo "  Version:  $version, for macOS $minimum_macos or later, Apple silicon and Intel"
case "$signing" in
    release) echo "  Signed:   release key, certificate $certificate" ;;
    local) echo "  Signed:   local build key, certificate $certificate. NOT A RELEASE." ;;
    adhoc) echo "  Signed:   no key. NOT A RELEASE." ;;
esac
echo "  Size:     $(stat -f %z "$dmg") bytes"
echo "  SHA-256:  $(shasum -a 256 "$dmg" | cut -d ' ' -f 1)"
