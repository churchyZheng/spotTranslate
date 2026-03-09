#!/bin/zsh

set -euo pipefail

# 安装到 ~/Applications，避免每次从 build 目录运行都被系统当成新应用实例。
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/build/SpotSentenceTranslate.app"
TARGET_DIR="$HOME/Applications"
TARGET_APP="$TARGET_DIR/SpotSentenceTranslate.app"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Missing app bundle: $SOURCE_APP"
  echo "Run ./scripts/build_app.sh first."
  exit 1
fi

mkdir -p "$TARGET_DIR"
rm -rf "$TARGET_APP"
cp -R "$SOURCE_APP" "$TARGET_APP"
xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true

echo "==> Opening installed app"
open "$TARGET_APP"

echo "==> Opening Accessibility settings"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

cat <<EOF

Installed to:
  $TARGET_APP

Next:
1. In System Settings > Privacy & Security > Accessibility, unlock the panel.
2. If SpotSentenceTranslate is listed, enable it.
3. If not listed, click '+', press Command+Shift+G, and paste:
   $TARGET_APP
4. Quit and reopen the app once after granting permission.

EOF
