#!/bin/bash
# 打包 FastImageView.app 并安装到 /Applications（或自定义目标目录）。
# 用法：Scripts/package-app.sh [目标目录]   （默认 /Applications）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="${1:-/Applications}"
APP_NAME="FastImageView"
BUNDLE="$ROOT/$APP_NAME.app"
ICON="$ROOT/AppIcon.icns"

cd "$ROOT"

echo "==> 构建 release"
swift build -c release

echo "==> 组装 $APP_NAME.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp ".build/release/$APP_NAME" "$BUNDLE/Contents/MacOS/$APP_NAME"

# Always take Support/Info.plist so CFBundleDocumentTypes stay registered for Finder “Open With”.
PLIST_SRC="$ROOT/Support/Info.plist"
if [ ! -f "$PLIST_SRC" ]; then
    echo "缺少 $PLIST_SRC" >&2
    exit 1
fi
cp "$PLIST_SRC" "$BUNDLE/Contents/Info.plist"

if [ -f "$ICON" ]; then
    cp "$ICON" "$BUNDLE/Contents/Resources/AppIcon.icns"
    plutil -replace CFBundleIconFile -string AppIcon "$BUNDLE/Contents/Info.plist"
fi

echo "==> ad-hoc 签名"
codesign --force --deep --sign - "$BUNDLE"
codesign --verify "$BUNDLE"

echo "==> 安装到 $DEST_DIR"
ditto "$BUNDLE" "$DEST_DIR/$APP_NAME.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST_DIR/$APP_NAME.app"

echo "完成：$DEST_DIR/$APP_NAME.app"
