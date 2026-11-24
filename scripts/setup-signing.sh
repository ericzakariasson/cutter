#!/bin/bash
# Creates the self-signed certificate that build-app.sh signs Cutter with. See signing.env
# for why. build-app.sh runs this for you; it does nothing when the certificate exists.
#
# To undo, delete the folder:  rm -rf "$HOME/Library/Application Support/Cutter/signing"
set -euo pipefail

source "$(dirname "$0")/signing.env"

if [ -f "$SIGNING_KEYCHAIN" ] &&
    security find-certificate -c "$SIGNING_IDENTITY" "$SIGNING_KEYCHAIN" >/dev/null 2>&1; then
    exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cat >"$work/certificate.conf" <<EOF
[req]
distinguished_name = subject
x509_extensions = extensions
prompt = no

[subject]
CN = $SIGNING_IDENTITY

[extensions]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$work/certificate.conf" \
    -keyout "$work/key.pem" -out "$work/certificate.pem" 2>/dev/null

/usr/bin/openssl pkcs12 -export \
    -inkey "$work/key.pem" -in "$work/certificate.pem" \
    -name "$SIGNING_IDENTITY" \
    -passout "pass:$SIGNING_KEYCHAIN_PASSWORD" \
    -out "$work/identity.p12"

mkdir -p "$SIGNING_HOME/Library/Preferences" "$SIGNING_HOME/Library/Keychains"
chmod 700 "$SIGNING_DIR"

if [ ! -f "$SIGNING_KEYCHAIN" ]; then
    security create-keychain -p "$SIGNING_KEYCHAIN_PASSWORD" "$SIGNING_KEYCHAIN"
fi
# No auto-lock, so a build does not stall on a locked keychain.
security set-keychain-settings "$SIGNING_KEYCHAIN"
security unlock-keychain -p "$SIGNING_KEYCHAIN_PASSWORD" "$SIGNING_KEYCHAIN"
security import "$work/identity.p12" \
    -k "$SIGNING_KEYCHAIN" \
    -P "$SIGNING_KEYCHAIN_PASSWORD" \
    -T /usr/bin/codesign >/dev/null
# Lets codesign use the key without a password dialog.
security set-key-partition-list -S apple-tool:,apple: -s \
    -k "$SIGNING_KEYCHAIN_PASSWORD" "$SIGNING_KEYCHAIN" >/dev/null

# The search list codesign sees when run with HOME="$SIGNING_HOME".
HOME="$SIGNING_HOME" security list-keychains -d user -s "$SIGNING_KEYCHAIN"

echo "Created signing certificate \"$SIGNING_IDENTITY\" in $SIGNING_DIR"
