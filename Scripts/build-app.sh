#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="OpenConnect VPN.app"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$PROJECT_DIR"

echo "Building OpenConnectVPN for Apple Silicon..."
swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_DIR/OpenConnectVPN" "$MACOS_DIR/OpenConnectVPN"
cp "$BIN_DIR/OpenConnectLauncher" "$MACOS_DIR/OpenConnectLauncher"
cp "$PROJECT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
iconutil -c icns "$PROJECT_DIR/Assets/AppIcon.iconset" -o "$RESOURCES_DIR/AppIcon.icns"

chmod 755 "$MACOS_DIR/OpenConnectVPN" "$MACOS_DIR/OpenConnectLauncher"
codesign --force --deep --sign - "$APP_DIR"

echo "Built: $APP_DIR"
