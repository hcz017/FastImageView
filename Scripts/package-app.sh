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

if [ ! -f "$BUNDLE/Contents/Info.plist" ]; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string en" "$BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $APP_NAME" "$BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string local.$APP_NAME" "$BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" "$BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.0" "$BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" "$BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 14.0" "$BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$BUNDLE/Contents/Info.plist"
fi

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
