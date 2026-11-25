#!/bin/bash
# Creates the key that signs Cutter releases. Run it once, in a terminal, on the Mac that
# makes the releases. See "The release key" in scripts/signing.env for why it exists.
#
#   ./scripts/setup-release-key.sh
#
# It asks for a passphrase, which locks the key and is stored nowhere, and writes the new
# certificate's fingerprint to Support/release-certificate.txt. Commit that file.
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/signing.env

if [ -e "$RELEASE_SIGNING_KEYCHAIN" ]; then
    echo "error: there is already a release key in $RELEASE_SIGNING_DIR." >&2
    echo "A new key would make everyone who installed a release grant Accessibility access again." >&2
    echo "To replace it all the same, move that folder away first." >&2
    exit 1
fi

read_passphrase "Passphrase for the release key (12 characters or more): "
if [ "${#passphrase}" -lt 12 ]; then
    echo "error: the passphrase needs 12 characters or more." >&2
    exit 1
fi
if [ -t 0 ]; then
    first="$passphrase"
    read_passphrase "The same passphrase again: "
    if [ "$passphrase" != "$first" ]; then
        echo "error: the two passphrases differ." >&2
        exit 1
    fi
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cat >"$work/certificate.conf" <<EOF
[req]
distinguished_name = subject
x509_extensions = extensions
prompt = no

[subject]
CN = $RELEASE_SIGNING_IDENTITY

[extensions]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 7300 \
    -config "$work/certificate.conf" \
    -keyout "$work/key.pem" -out "$work/certificate.pem" 2>/dev/null

# The key travels into the keychain in a file that exists for a moment, in a folder only
# this user can read, under a password made up for the occasion.
transfer_password="$(/usr/bin/openssl rand -hex 24)"
/usr/bin/openssl pkcs12 -export \
    -inkey "$work/key.pem" -in "$work/certificate.pem" \
    -name "$RELEASE_SIGNING_IDENTITY" \
    -passout "pass:$transfer_password" \
    -out "$work/identity.p12"

mkdir -p "$RELEASE_SIGNING_HOME/Library/Preferences" "$RELEASE_SIGNING_HOME/Library/Keychains"
chmod 700 "$RELEASE_SIGNING_DIR"

security_unseen create-keychain -p "$passphrase" "$RELEASE_SIGNING_KEYCHAIN"
# Locks by itself after a minute and when the Mac sleeps.
security set-keychain-settings -l -u -t 60 "$RELEASE_SIGNING_KEYCHAIN"
security import "$work/identity.p12" \
    -k "$RELEASE_SIGNING_KEYCHAIN" \
    -P "$transfer_password" \
    -T /usr/bin/codesign >/dev/null
# Lets codesign use the key, once the keychain is unlocked, without a dialog of its own.
security_unseen set-key-partition-list -S apple-tool:,apple: -s \
    -k "$passphrase" "$RELEASE_SIGNING_KEYCHAIN" >/dev/null
# The search list codesign sees when run with HOME="$RELEASE_SIGNING_HOME".
HOME="$RELEASE_SIGNING_HOME" security list-keychains -d user -s "$RELEASE_SIGNING_KEYCHAIN"
security lock-keychain "$RELEASE_SIGNING_KEYCHAIN"

certificate="$(/usr/bin/openssl x509 -in "$work/certificate.pem" -noout -fingerprint -sha1 |
    sed 's/.*=//' | tr -d ':' | tr 'A-F' 'a-f')"
{
    grep '^#' Support/release-certificate.txt
    echo "$certificate"
} >"$work/release-certificate.txt"
cp "$work/release-certificate.txt" Support/release-certificate.txt

echo "Created the release key in $RELEASE_SIGNING_DIR"
echo "Certificate: $certificate (written to Support/release-certificate.txt; commit it)"
echo "Back up that folder and keep the passphrase somewhere safe. Neither can be recovered."
