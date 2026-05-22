#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

CONFIGURATION="${DEPLOYBAR_BUILD_CONFIGURATION:-debug}"
APP_VERSION="${DEPLOYBAR_VERSION:-0.1.0}"
BUILD_NUMBER="${DEPLOYBAR_BUILD_NUMBER:-1}"

swift build -c "$CONFIGURATION" --product DeployBar

APP_DIR="$ROOT_DIR/.build/DeployBar.app"
EXECUTABLE="$ROOT_DIR/.build/$CONFIGURATION/DeployBar"
RESOURCES_DIR="$ROOT_DIR/Sources/DeployBar/Resources"
ICON_FILE="$RESOURCES_DIR/DeployBar.icns"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/DeployBar"
if [[ -d "$RESOURCES_DIR" ]]; then
  ditto "$RESOURCES_DIR" "$APP_DIR/Contents/Resources"
  find "$APP_DIR/Contents/Resources" \( -name ".DS_Store" -o -name ".gitkeep" \) -delete
fi
if [[ -f "$ICON_FILE" ]]; then
  cp "$ICON_FILE" "$APP_DIR/Contents/Resources/DeployBar.icns"
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>DeployBar</string>
  <key>CFBundleIdentifier</key>
  <string>com.deploybar.app</string>
  <key>CFBundleName</key>
  <string>DeployBar</string>
  <key>CFBundleIconFile</key>
  <string>DeployBar.icns</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 DeployBar contributors.</string>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  SIGN_IDENTITY="${DEPLOYBAR_CODE_SIGN_IDENTITY:-}"
  if [[ -n "$SIGN_IDENTITY" ]]; then
    codesign --remove-signature "$APP_DIR/Contents/MacOS/DeployBar" >/dev/null 2>&1 || true
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR" >/dev/null
  elif [[ "${DEPLOYBAR_AD_HOC_SIGN:-0}" == "1" ]]; then
    codesign --remove-signature "$APP_DIR/Contents/MacOS/DeployBar" >/dev/null 2>&1 || true
    codesign --force --deep --sign - "$APP_DIR" >/dev/null
  else
    echo "Skipping ad-hoc codesign; set DEPLOYBAR_AD_HOC_SIGN=1 to force it or DEPLOYBAR_CODE_SIGN_IDENTITY to use a stable identity."
  fi
fi

echo "Built $APP_DIR"
