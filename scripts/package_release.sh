#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$(cd "$PROJECT_DIR/../.." && pwd)/outputs"
APP_NAME="Autonomer KI-Gruppenchat"
VERSION="18.1.1"
APP_PATH="${TMPDIR%/}/AutonomousAIChat-v18-app-build/$APP_NAME.app"
DMG_PATH="$OUTPUT_DIR/AutonomousAIChat-v$VERSION.dmg"
UPDATE_ZIP_PATH="$OUTPUT_DIR/AutonomousAIChat-v$VERSION-update.zip"
SOURCE_ZIP_PATH="$OUTPUT_DIR/AutonomousAIChat-v18.zip"
STAGING_DIR="$(mktemp -d /tmp/autonomous-ai-chat-release.XXXXXX)"
CLEAN_APP_PATH="$STAGING_DIR/clean/$APP_NAME.app"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR"
"$PROJECT_DIR/start.command" --build-only

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose=2 "$APP_PATH" || true

mkdir -p "$STAGING_DIR/clean"
ditto --noextattr "$APP_PATH" "$CLEAN_APP_PATH"
xattr -cr "$CLEAN_APP_PATH" 2>/dev/null || true
codesign --verify --deep --strict --verbose=2 "$CLEAN_APP_PATH"

rm -f "$DMG_PATH" "$UPDATE_ZIP_PATH" "$SOURCE_ZIP_PATH"

mkdir -p "$STAGING_DIR/dmg"
ditto --noextattr "$CLEAN_APP_PATH" "$STAGING_DIR/dmg/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/dmg/Applications"
hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$STAGING_DIR/dmg" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

ditto -c -k --sequesterRsrc --keepParent "$CLEAN_APP_PATH" "$UPDATE_ZIP_PATH"

mkdir -p "$STAGING_DIR/source/AutonomousAIChat-v18"
rsync -a \
  --exclude '.git' \
  --exclude '.build' \
  --exclude '.app-build' \
  --exclude '.swiftpm' \
  --exclude '.DS_Store' \
  "$PROJECT_DIR/" "$STAGING_DIR/source/AutonomousAIChat-v18/"
ditto -c -k --norsrc --keepParent \
  "$STAGING_DIR/source/AutonomousAIChat-v18" "$SOURCE_ZIP_PATH"

hdiutil verify "$DMG_PATH"
unzip -tq "$UPDATE_ZIP_PATH"
unzip -tq "$SOURCE_ZIP_PATH"
mkdir -p "$STAGING_DIR/update-check"
ditto -x -k "$UPDATE_ZIP_PATH" "$STAGING_DIR/update-check"
codesign --verify --deep --strict --verbose=2 \
  "$STAGING_DIR/update-check/$APP_NAME.app"
shasum -a 256 "$DMG_PATH" "$UPDATE_ZIP_PATH" "$SOURCE_ZIP_PATH"
