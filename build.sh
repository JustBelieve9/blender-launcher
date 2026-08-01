#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Blender Launcher"
BIN_NAME="BlenderLauncher"
APP_DIR="$APP_NAME.app"

swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp ".build/release/$BIN_NAME" "$APP_DIR/Contents/MacOS/$BIN_NAME"
cp "Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

codesign --force --deep -s - "$APP_DIR"

echo "Built: $APP_DIR"
