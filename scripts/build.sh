#!/bin/bash
# Builds build/Lyrik.app (release, Apple silicon, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT="$PWD"
APP="$ROOT/build/Lyrik.app"
WORK="$ROOT/build/work"
CONFIG="${CONFIG:-release}"

echo "==> Compiling Swift ($CONFIG)"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Lyrik"

mkdir -p "$WORK"

echo "==> Rendering icon"
if [ ! -f "$WORK/AppIcon.icns" ] || [ scripts/make-icon.swift -nt "$WORK/AppIcon.icns" ]; then
  rm -rf "$WORK/AppIcon.iconset"
  swift scripts/make-icon.swift "$WORK/AppIcon.iconset"
  iconutil -c icns "$WORK/AppIcon.iconset" -o "$WORK/AppIcon.icns"
fi

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Lyrik"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$WORK/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing (ad-hoc, hardened runtime)"
codesign --force --options runtime --entitlements Resources/Lyrik.entitlements --sign - "$APP"
codesign --verify --strict "$APP"

echo "==> Built $APP"
