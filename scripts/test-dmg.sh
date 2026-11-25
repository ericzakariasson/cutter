#!/bin/bash
# Checks scripts/make-dmg.sh and scripts/setup-release-key.sh end to end, with a throwaway
# release key in a temporary folder. The real release key is never touched, nothing opens
# on screen, and Support/release-certificate.txt is put back afterwards.
#
#   ./scripts/test-dmg.sh
set -euo pipefail

cd "$(dirname "$0")/.."

work="$(mktemp -d)"
cp Support/release-certificate.txt "$work/release-certificate.txt"
restore() {
    cp "$work/release-certificate.txt" Support/release-certificate.txt
    rm -rf "$work" dist
}
trap restore EXIT

export CUTTER_RELEASE_SIGNING_DIR="$work/a folder with spaces/key"
unset CUTTER_SIGNING CUTTER_RELEASE_KEY
passphrase='a "quoted" pass\phrase'
version="$(plutil -extract CFBundleShortVersionString raw Support/Info.plist)"

failures=0
check() {
    if eval "$2"; then
        echo "ok    $1"
    else
        echo "FAIL  $1"
        failures=$((failures + 1))
    fi
}
# Runs make-dmg.sh with a line of standard input; keeps its output and exit status.
make_dmg() {
    status=0
    printf '%s\n' "$1" | ./scripts/make-dmg.sh >"$work/output.txt" 2>&1 || status=$?
}
dmgs() {
    ls dist 2>/dev/null | grep '\.dmg$' | tr '\n' ' ' || true
}

make_dmg ""
check "without a release key, the default stops and says how to make one" \
    '[ "$status" -ne 0 ] && grep -q "setup-release-key.sh" "$work/output.txt" && [ -z "$(dmgs)" ]'

check "a short passphrase is refused" \
    '! printf "short\n" | ./scripts/setup-release-key.sh >/dev/null 2>&1 && [ ! -e "$CUTTER_RELEASE_SIGNING_DIR" ]'

printf '%s\n' "$passphrase" | ./scripts/setup-release-key.sh >"$work/setup.txt" 2>&1
certificate="$(grep -v '^#' Support/release-certificate.txt | tr -d '[:space:]')"
check "setup writes the new certificate to Support/release-certificate.txt" \
    '[ "${#certificate}" -eq 40 ] && grep -q "$certificate" "$work/setup.txt"'
check "setup refuses to replace an existing release key" \
    '! printf "%s\n" "$passphrase" | ./scripts/setup-release-key.sh >/dev/null 2>&1'

make_dmg "not the passphrase"
check "a wrong passphrase stops before anything is signed or packaged" \
    '[ "$status" -ne 0 ] && grep -q "does not unlock" "$work/output.txt" && [ -z "$(dmgs)" ]'

make_dmg "$passphrase"
check "the right passphrase makes Cutter-$version.dmg, signed with the release key" \
    '[ "$status" -eq 0 ] && [ "$(dmgs)" = "Cutter-$version.dmg " ] && grep -q "release key, certificate $certificate" "$work/output.txt"'
check "the app is signed with that certificate" \
    'codesign --display --requirements - dist/Cutter.app 2>/dev/null | grep -q "certificate leaf = H\"$certificate\""'

{
    grep '^#' "$work/release-certificate.txt"
    echo "0000000000000000000000000000000000000000"
} >Support/release-certificate.txt
make_dmg "$passphrase"
check "a key other than the one on record is refused, and no DMG is left behind" \
    '[ "$status" -ne 0 ] && grep -q "not the release key" "$work/output.txt" && [ -z "$(dmgs)" ]'

status=0
CUTTER_SIGNING=adhoc ./scripts/make-dmg.sh >"$work/output.txt" 2>&1 </dev/null || status=$?
check "CUTTER_SIGNING=adhoc needs no key and says so in the name" \
    '[ "$status" -eq 0 ] && [ "$(dmgs)" = "Cutter-$version-adhoc.dmg " ] && grep -q "NOT A RELEASE" "$work/output.txt"'

if [ "$failures" -gt 0 ]; then
    echo "$failures check(s) failed."
    exit 1
fi
echo "All checks passed."
