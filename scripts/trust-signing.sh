#!/usr/bin/env bash
# Run this yourself once, after scripts/setup-signing.sh. It marks the TodoPet certificate as trusted
# for code signing, for your user account only (not for websites or anything else).
# macOS asks for your password to confirm. Undo: Keychain Access → find "TodoPet Local Signing" → delete,
# or remove ~/Library/Application Support/TodoPet-Signing.
set -euo pipefail

KEYCHAIN="$HOME/Library/Application Support/TodoPet-Signing/signing.keychain-db"
[[ -f "$KEYCHAIN" ]] || { echo "Run scripts/setup-signing.sh first."; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
security find-certificate -c "TodoPet Local Signing" -p "$KEYCHAIN" > "$TMP/cert.pem"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"
echo "Done: \"TodoPet Local Signing\" is trusted for code signing. Rebuild with scripts/build.sh."
