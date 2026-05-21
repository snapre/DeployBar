#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

swift build -c debug --product DeployBar

APP_DIR="$ROOT_DIR/.build/DeployBar.app"
EXECUTABLE="$ROOT_DIR/.build/debug/DeployBar"
ICON_FILE="$ROOT_DIR/Sources/DeployBar/Resources/DeployBar.icns"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/DeployBar"
if [[ -f "$ICON_FILE" ]]; then
  cp "$ICON_FILE" "$APP_DIR/Contents/Resources/DeployBar.icns"
fi

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
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
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
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
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR" >/dev/null
  elif [[ "${DEPLOYBAR_AD_HOC_SIGN:-0}" == "1" ]]; then
    codesign --force --deep --sign - "$APP_DIR" >/dev/null
  else
    echo "Skipping ad-hoc codesign; set DEPLOYBAR_AD_HOC_SIGN=1 to force it or DEPLOYBAR_CODE_SIGN_IDENTITY to use a stable identity."
  fi
fi

echo "Built $APP_DIR"
