#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

CONFIGURATION="${DEPLOYBAR_BUILD_CONFIGURATION:-debug}"
APP_VERSION="${DEPLOYBAR_VERSION:-0.1.0}"
BUILD_NUMBER="${DEPLOYBAR_BUILD_NUMBER:-1}"
BUILD_ARCHS_VALUE="${DEPLOYBAR_BUILD_ARCHS-arm64 x86_64}"
IFS=' ' read -r -a BUILD_ARCHS <<< "$BUILD_ARCHS_VALUE"

BUILD_ARGS=(-c "$CONFIGURATION" --product DeployBar)
for ARCH in "${BUILD_ARCHS[@]}"; do
  BUILD_ARGS+=(--arch "$ARCH")
done

swift build "${BUILD_ARGS[@]}"

APP_DIR="$ROOT_DIR/.build/DeployBar.app"
if [[ ${#BUILD_ARCHS[@]} -gt 0 ]]; then
  case "$CONFIGURATION" in
    debug)
      PRODUCT_CONFIGURATION="Debug"
      ;;
    release)
      PRODUCT_CONFIGURATION="Release"
      ;;
    *)
      echo "Unsupported build configuration: $CONFIGURATION" >&2
      exit 1
      ;;
  esac
  EXECUTABLE="$ROOT_DIR/.build/apple/Products/$PRODUCT_CONFIGURATION/DeployBar"
else
  EXECUTABLE="$ROOT_DIR/.build/$CONFIGURATION/DeployBar"
fi
RESOURCES_DIR="$ROOT_DIR/Sources/DeployBar/Resources"
ICON_FILE="$RESOURCES_DIR/DeployBar.icns"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/DeployBar"
if [[ ${#BUILD_ARCHS[@]} -gt 0 ]] && command -v lipo >/dev/null 2>&1; then
  lipo "$APP_DIR/Contents/MacOS/DeployBar" -verify_arch "${BUILD_ARCHS[@]}"
fi
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
  <string>13.0</string>
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
    SIGN_KEYCHAIN="${DEPLOYBAR_CODE_SIGN_KEYCHAIN:-}"
    codesign --remove-signature "$APP_DIR/Contents/MacOS/DeployBar" >/dev/null 2>&1 || true
    if [[ -n "$SIGN_KEYCHAIN" ]]; then
      codesign --force --deep --options runtime --timestamp --keychain "$SIGN_KEYCHAIN" --sign "$SIGN_IDENTITY" "$APP_DIR" >/dev/null
    else
      codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR" >/dev/null
    fi
  elif [[ "${DEPLOYBAR_AD_HOC_SIGN:-1}" == "1" ]]; then
    codesign --remove-signature "$APP_DIR/Contents/MacOS/DeployBar" >/dev/null 2>&1 || true
    codesign --force --deep --sign - "$APP_DIR" >/dev/null
  else
    echo "Skipping codesign; set DEPLOYBAR_AD_HOC_SIGN=1 for local signing or DEPLOYBAR_CODE_SIGN_IDENTITY to use a stable identity."
  fi
fi

echo "Built $APP_DIR"
