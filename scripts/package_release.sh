#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DERIVED_DATA/Build/Products/Release/PortBar.app"
ZIP_PATH="$DIST_DIR/PortBar.zip"

cd "$ROOT_DIR"

xcodegen generate
xcodebuild \
  -project PortBar.xcodeproj \
  -scheme PortBar \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  build

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "$ZIP_PATH"
