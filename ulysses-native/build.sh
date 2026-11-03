#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

APP=build/UlyssesNative.app
SDKROOT_DIR=/Library/Developer/CommandLineTools/SDKs
MODULECACHE="$PWD/.modulecache"
mkdir -p "$MODULECACHE"

# 这台机器装了完整 Xcode 但没接受许可协议，xcode-select 又指向它，
# 于是 /usr/bin/swiftc 和 /usr/bin/git 都会直接报 "You have not agreed to the Xcode license"。
# 我们只需要 Command Line Tools 的编译器，所以显式用它，并导出 DEVELOPER_DIR 让子工具也走 CLT。
CLT=/Library/Developer/CommandLineTools
export DEVELOPER_DIR="$CLT"
SWIFTC="$CLT/usr/bin/swiftc"
[ -x "$SWIFTC" ] || SWIFTC="$(command -v swiftc)"

printf 'import AppKit\nprint("ok")\n' > .probe.swift
CHOSEN=""
for s in MacOSX27.0.sdk MacOSX27.sdk MacOSX26.sdk MacOSX26.5.sdk MacOSX26.0.sdk MacOSX15.5.sdk MacOSX15.2.sdk MacOSX.sdk; do
    [ -d "$SDKROOT_DIR/$s" ] || continue
    if SDKROOT="$SDKROOT_DIR/$s" "$SWIFTC" -module-cache-path "$MODULECACHE" -o "$MODULECACHE/probe.out" .probe.swift >/dev/null 2>&1; then
        CHOSEN="$s"; break
    fi
done
rm -f .probe.swift
[ -n "$CHOSEN" ] || { echo "没有找到匹配的 SDK"; exit 1; }
echo "使用 SDK: $CHOSEN"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
[ -f icons/AppIcon.icns ] && cp icons/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns" || echo "（暂无图标，跳过）"

SDKROOT="$SDKROOT_DIR/$CHOSEN" "$SWIFTC" -O -module-cache-path "$MODULECACHE" \
    -o "$APP/Contents/MacOS/ulysses-native" Sources/*.swift -framework AppKit

codesign --force --sign - "$APP" 2>/dev/null || true
echo "构建完成: $PWD/$APP"
