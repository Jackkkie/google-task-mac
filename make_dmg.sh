#!/bin/bash
set -e

APP_NAME="GoogleTask"
DMG_NAME="GoogleTasks"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "▶ Searching for built app..."
ALL=$(find ~/Library/Developer/Xcode/DerivedData -name "$APP_NAME.app" 2>/dev/null)
echo "Found: $ALL"

APP_PATH=$(echo "$ALL" | grep "maccatalyst" | grep -v ".XCInstall" | head -1)
if [ -z "$APP_PATH" ]; then
  APP_PATH=$(echo "$ALL" | grep -v ".XCInstall" | head -1)
fi

if [ -z "$APP_PATH" ]; then
  echo "❌ App not found. Build in Xcode first (Cmd+B)."
  exit 1
fi

echo "✓ Found app: $APP_PATH"
echo "▶ Creating DMG..."

STAGING="/tmp/${DMG_NAME}_staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -r "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

DMG_OUT="$PROJECT_DIR/${DMG_NAME}.dmg"
rm -f "$DMG_OUT"
hdiutil create \
  -volname "$DMG_NAME" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG_OUT"

rm -rf "$STAGING"
echo "✅ Done: $DMG_OUT"
