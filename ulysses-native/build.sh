#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

APP=build/UlyssesNative.app
SDKROOT_DIR=/Library/Developer/CommandLineTools/SDKs
MODULECACHE="$PWD/.modulecache"
mkdir -p "$MODULECACHE"

printf 'import AppKit\nprint("ok")\n' > .probe.swift
CHOSEN=""
for s in MacOSX27.0.sdk MacOSX27.sdk MacOSX26.sdk MacOSX26.5.sdk MacOSX26.0.sdk MacOSX15.5.sdk MacOSX15.2.sdk MacOSX.sdk; do
    [ -d "$SDKROOT_DIR/$s" ] || continue
    if SDKROOT="$SDKROOT_DIR/$s" swiftc -module-cache-path "$MODULECACHE" -o "$MODULECACHE/probe.out" .probe.swift >/dev/null 2>&1; then
        CHOSEN="$s"; break
    fi
done
rm -f .probe.swift
[ -n "$CHOSEN" ] || { echo "没有找到匹配的 SDK"; exit 1; }
echo "使用 SDK: $CHOSEN"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"

SDKROOT="$SDKROOT_DIR/$CHOSEN" swiftc -O -module-cache-path "$MODULECACHE" \
    -o "$APP/Contents/MacOS/ulysses-native" main.swift -framework AppKit

codesign --force --sign - "$APP" 2>/dev/null || true
echo "构建完成: $PWD/$APP"
