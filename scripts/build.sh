#!/usr/bin/env bash
# Builds build/TodoPet.app with the Xcode Command Line Tools (no Xcode project needed).
#   scripts/build.sh            # native architecture
#   UNIVERSAL=1 scripts/build.sh  # arm64 + x86_64
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
APP="build/TodoPet.app"
MIN_MACOS="14.0"
SOURCES=(Sources/TodoPet/*.swift)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj

compile() {
  local arch="$1" out="$2"
  swiftc -O -swift-version 5 -target "$arch-apple-macos$MIN_MACOS" \
    -module-name TodoPet -o "$out" "${SOURCES[@]}"
}

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  compile arm64 build/obj/TodoPet-arm64
  compile x86_64 build/obj/TodoPet-x86_64
  lipo -create build/obj/TodoPet-arm64 build/obj/TodoPet-x86_64 -output "$APP/Contents/MacOS/TodoPet"
else
  compile "$(uname -m)" "$APP/Contents/MacOS/TodoPet"
fi

sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
for lproj in Resources/*.lproj; do
  if [[ -d "$lproj" ]]; then cp -R "$lproj" "$APP/Contents/Resources/"; fi
done

# Sign with the stable local certificate when it exists (scripts/setup-signing.sh), so macOS keeps
# granted permissions across rebuilds; otherwise fall back to an ad-hoc signature.
SIGN_DIR="$HOME/Library/Application Support/TodoPet-Signing"
signed=0
if [[ -f "$SIGN_DIR/signing.keychain-db" && -f "$SIGN_DIR/keychain-password" ]]; then
  security unlock-keychain -p "$(cat "$SIGN_DIR/keychain-password")" "$SIGN_DIR/signing.keychain-db"
  if codesign --force --sign "TodoPet Local Signing" --keychain "$SIGN_DIR/signing.keychain-db" \
       --identifier com.todopet.mochi "$APP" 2>/dev/null; then
    signed=1
    echo "Built $APP (signed with TodoPet Local Signing)"
  else
    echo "Note: the TodoPet certificate isn't trusted for code signing yet; run scripts/trust-signing.sh once."
  fi
else
  echo "Note: run scripts/setup-signing.sh once to stop permission prompts after each rebuild."
fi
if [[ $signed == 0 ]]; then
  codesign --force --sign - --identifier com.todopet.mochi "$APP" 2>/dev/null
  echo "Built $APP (ad-hoc signed)"
fi
