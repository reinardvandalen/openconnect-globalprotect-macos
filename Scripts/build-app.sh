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
LOCALIZATION_BUNDLE_NAME="OpenConnectVPN_OpenConnectCore.bundle"
LOCALIZATION_BUNDLE="$BIN_DIR/$LOCALIZATION_BUNDLE_NAME"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_DIR/OpenConnectVPN" "$MACOS_DIR/OpenConnectVPN"
cp "$BIN_DIR/OpenConnectLauncher" "$MACOS_DIR/OpenConnectLauncher"
cp "$PROJECT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
iconutil -c icns "$PROJECT_DIR/Assets/AppIcon.iconset" -o "$RESOURCES_DIR/AppIcon.icns"

if [[ ! -d "$LOCALIZATION_BUNDLE" ]]; then
    echo "Missing localization bundle: $LOCALIZATION_BUNDLE" >&2
    exit 1
fi
ditto "$LOCALIZATION_BUNDLE" "$RESOURCES_DIR/$LOCALIZATION_BUNDLE_NAME"

for language in en nl de; do
    strings_file="$RESOURCES_DIR/$LOCALIZATION_BUNDLE_NAME/$language.lproj/Localizable.strings"
    if [[ ! -f "$strings_file" ]]; then
        echo "Missing localization: $strings_file" >&2
        exit 1
    fi
done

chmod 755 "$MACOS_DIR/OpenConnectVPN" "$MACOS_DIR/OpenConnectLauncher"
codesign --force --deep --sign - "$APP_DIR"

echo "Built: $APP_DIR"
