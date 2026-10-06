#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/module-cache build/AppIcon.iconset
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
ARCH="${ARCH:-$(uname -m)}"
APP="$PWD/build/Negative Harmony MIDI Converter.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -swift-version 5 -O -target "$ARCH-apple-macosx13.0" -module-cache-path "$CLANG_MODULE_CACHE_PATH" Sources/NegativeHarmony/*.swift -o "$APP/Contents/MacOS/NegativeHarmony"
xcrun swiftc -module-cache-path "$CLANG_MODULE_CACHE_PATH" Resources/DrawIcon.swift -o build/draw-icon
build/draw-icon Resources/AppIcon.png
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/AppIcon.png --out "build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" Resources/AppIcon.png --out "build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
printf 'Built: %s\n' "$APP"
