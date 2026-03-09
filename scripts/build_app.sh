#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="SpotSentenceTranslate"
BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
EXECUTABLE_PATH="$ROOT_DIR/.build/release/$APP_NAME"
TEMP_ROOT="${TMPDIR%/}/spot-sentence-translate-build"
BUNDLE_IDENTIFIER="com.spottranslate.app"

mkdir -p \
  "$TEMP_ROOT/home" \
  "$TEMP_ROOT/clang-module-cache" \
  "$TEMP_ROOT/swiftpm-cache" \
  "$TEMP_ROOT/swiftpm-config" \
  "$TEMP_ROOT/swiftpm-security"

echo "==> Building release binary"
HOME="$TEMP_ROOT/home" \
CLANG_MODULE_CACHE_PATH="$TEMP_ROOT/clang-module-cache" \
swift build \
  --package-path "$ROOT_DIR" \
  --disable-sandbox \
  -c release \
  --cache-path "$TEMP_ROOT/swiftpm-cache" \
  --config-path "$TEMP_ROOT/swiftpm-config" \
  --security-path "$TEMP_ROOT/swiftpm-security"

echo "==> Packaging app bundle"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$EXECUTABLE_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Support/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "==> Applying stable ad-hoc signature"
codesign \
  --force \
  --deep \
  --sign - \
  --requirements "=designated => identifier \"$BUNDLE_IDENTIFIER\"" \
  --timestamp=none \
  "$APP_BUNDLE" \
  >/dev/null

echo "Built: $APP_BUNDLE"
