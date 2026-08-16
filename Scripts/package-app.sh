#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$PROJECT_DIR/dist/OpenConnect VPN.app"
ZIP_PATH="$PROJECT_DIR/dist/OpenConnectVPN-arm64.zip"

"$SCRIPT_DIR/build-app.sh"

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "Packaged: $ZIP_PATH"
