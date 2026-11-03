#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

APP=build/UlyssesLite.app
SRC_HTML=../ulysses-lite.html
SDKROOT_DIR=/Library/Developer/CommandLineTools/SDKs
MODULECACHE="$PWD/.modulecache"

[ -f "$SRC_HTML" ] || { echo "找不到 $SRC_HTML"; exit 1; }
mkdir -p "$MODULECACHE"

# 自动选一个与当前 swiftc 匹配的 SDK（CLT 安装可能存在编译器/SDK 版本错配）
printf 'import AppKit\nimport WebKit\nimport Network\nprint("ok")\n' > .probe.swift
CHOSEN=""
for s in MacOSX27.0.sdk MacOSX27.sdk MacOSX26.sdk MacOSX26.5.sdk MacOSX26.0.sdk MacOSX15.5.sdk MacOSX15.2.sdk MacOSX.sdk; do
    [ -d "$SDKROOT_DIR/$s" ] || continue
    if SDKROOT="$SDKROOT_DIR/$s" swiftc -module-cache-path "$MODULECACHE" -o "$MODULECACHE/probe.out" .probe.swift >/dev/null 2>&1; then
        CHOSEN="$s"
        break
    fi
done
rm -f .probe.swift
[ -n "$CHOSEN" ] || { echo "没有找到匹配的 SDK，无法编译。"; exit 1; }
echo "使用 SDK: $CHOSEN"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$SRC_HTML" "$APP/Contents/Resources/index.html"
cp Info.plist "$APP/Contents/Info.plist"

# 图标：icon.iconset 已存在则转 icns
if [ -d icon.iconset ]; then
    iconutil -c icns icon.iconset -o "$APP/Contents/Resources/AppIcon.icns" || echo "（图标转换失败，先跳过）"
fi

SDKROOT="$SDKROOT_DIR/$CHOSEN" swiftc -O -module-cache-path "$MODULECACHE" \
    -o "$APP/Contents/MacOS/ulysses-lite" main.swift \
    -framework AppKit -framework WebKit -framework Network

codesign --force --sign - "$APP" 2>/dev/null || true

echo "构建完成: $PWD/$APP"
