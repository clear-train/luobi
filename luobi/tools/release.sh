#!/usr/bin/env bash
# 打一个可以发给别人（也能自己存档）的 macOS 安装包。
#
#   ./tools/release.sh            只打包：dist/Luobi-<版本>.zip 和 .dmg
#   ./tools/release.sh --publish  打包 + 顺手用 gh 发一个 GitHub Release
#
# 产物：
#   dist/Luobi-<版本>-macOS.zip   ← 别人下载后解压、拖进「应用程序」即可
#   dist/Luobi-<版本>.dmg         ← 双击挂载，把 App 拖到 Applications
#
set -euo pipefail
cd "$(dirname "$0")/.."

PUBLISH=0
[ "${1:-}" = "--publish" ] && PUBLISH=1

# ---- 版本号：直接从 Info.plist 读，作为唯一真相 ----
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Info.plist)
echo "==> 版本 $VER (build $BUILD)"

# ---- 1. 干净编译 + 临时签名（build.sh 里已做 ad-hoc codesign）----
./build.sh
APP="build/Luobi.app"
[ -d "$APP" ] || { echo "构建产物不存在"; exit 1; }

# ---- 2. 归档成 zip（ditto 保留 bundle 结构、权限与扩展属性）----
DIST="dist"
rm -rf "$DIST"
mkdir -p "$DIST"
ZIP="$DIST/Luobi-$VER-macOS.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
echo "==> $ZIP ($(du -h "$ZIP" | cut -f1))"

# ---- 3. 做 dmg：里面放 App + 一个指向 /Applications 的快捷方式 ----
STAGE="$DIST/.stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$DIST/Luobi-$VER.dmg"
if command -v hdiutil >/dev/null 2>&1; then
    if hdiutil create -quiet -volname "落笔" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null 2>&1; then
        echo "==> $DMG ($(du -h "$DMG" | cut -f1))"
    else
        echo "==> dmg 制作失败（沙箱通常会拦 hdiutil），zip 仍然可用"
    fi
else
    echo "==> 没有 hdiutil，跳过 dmg"
fi
rm -rf "$STAGE"

# ---- 4. 校验和 + 安装说明 ----
echo
echo "SHA-256："
shasum -a 256 "$DIST"/* 2>/dev/null || true
echo
cat <<TXT
安装方法（发给别人也一样）：
  1. 解压 zip（或双击 dmg 挂载）
  2. 把 Luobi.app 拖进「应用程序」
  3. 第一次打开：右键 App → 打开（因为没做 Apple 公证，双击会被 Gatekeeper 拦一次）；
     或者在终端跑：xattr -dr com.apple.quarantine "/Applications/Luobi.app"
  4. 文稿库在 ~/Library/Application Support/Luobi/state.json，备份拷这个文件即可
TXT

# ---- 5. 可选：发 GitHub Release ----
if [ "$PUBLISH" = 1 ]; then
    command -v gh >/dev/null 2>&1 || { echo "没装 gh，跳过发布"; exit 0; }
    REPO=$(git config --get remote.origin.url | sed -E 's#.*github.com[:/]##; s#\.git$##')
    TAG="v$VER"
    gh release list --repo "$REPO" | grep -q "$TAG" && { echo "Release $TAG 已存在，先改 Info.plist 里的版本号"; exit 1; }
    ASSETS=("$ZIP")
    [ -f "$DMG" ] && ASSETS+=("$DMG")
    gh release create "$TAG" "${ASSETS[@]}" \
        --repo "$REPO" \
        --title "落笔 $VER" \
        --notes "写作工具 落笔 ${VER}：分组树侧栏、可收起侧栏、四套配色与字号、Markdown 实时排版、打字机模式、首次启动引导."
    echo "==> 已发布：https://github.com/$REPO/releases/tag/$TAG"
fi
