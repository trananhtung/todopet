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

codesign --force --sign - --identifier com.todopet.mochi "$APP" >/dev/null
echo "Built $APP"
