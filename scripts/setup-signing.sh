#!/usr/bin/env bash
# One-time setup: creates a self-signed code-signing certificate for TodoPet in its own keychain.
# With it every build carries the same signature, so macOS remembers the Keychain, Calendar and
# browser permissions you granted instead of asking again after each update.
# Nothing here touches your login keychain; delete the folder below to undo.
set -euo pipefail

NAME="TodoPet Local Signing"
DIR="$HOME/Library/Application Support/TodoPet-Signing"
KEYCHAIN="$DIR/signing.keychain-db"
PWFILE="$DIR/keychain-password"

if [[ -f "$KEYCHAIN" ]]; then
  echo "Already set up: $KEYCHAIN"
  exit 0
fi

mkdir -p "$DIR"
chmod 700 "$DIR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A random password for the dedicated keychain, which holds nothing but this certificate.
PW="$(openssl rand -base64 24)"
(umask 077 && printf '%s' "$PW" > "$PWFILE")

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
P12PW="$(openssl rand -base64 18)"
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -out "$TMP/identity.p12" -passout "pass:$P12PW"

security create-keychain -p "$PW" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"   # no auto-lock
security unlock-keychain -p "$PW" "$KEYCHAIN"
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$P12PW" -T /usr/bin/codesign >/dev/null
# Let codesign use the key without a password prompt.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PW" "$KEYCHAIN" >/dev/null

echo "Created \"$NAME\" in $KEYCHAIN"
