#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Autonomer KI-Gruppenchat"
BUILD_DIR="${TMPDIR%/}/AutonomousAIChat-v18-app-build"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
SWIFT_BUILD_DIR="${TMPDIR%/}/AutonomousAIChat-v18-swift-build"
EXECUTABLE="$SWIFT_BUILD_DIR/release/AutonomousAIChat"
SPARKLE_FRAMEWORK="$SWIFT_BUILD_DIR/release/Sparkle.framework"
ASSEMBLY_DIR="$(mktemp -d /tmp/autonomous-ai-chat-app.XXXXXX)"
ASSEMBLED_APP_PATH="$ASSEMBLY_DIR/$APP_NAME.app"

cleanup() {
  rm -rf "$ASSEMBLY_DIR"
}
trap cleanup EXIT

if ! command -v swift >/dev/null 2>&1; then
  echo "❌ Swift wurde nicht gefunden. Bitte Xcode oder die Xcode Command Line Tools installieren."
  exit 1
fi

echo "🔨 Baue $APP_NAME …"
swift build --scratch-path "$SWIFT_BUILD_DIR" -c release

mkdir -p "$ASSEMBLED_APP_PATH/Contents/MacOS" "$ASSEMBLED_APP_PATH/Contents/Resources" "$ASSEMBLED_APP_PATH/Contents/Frameworks"
cp "$EXECUTABLE" "$ASSEMBLED_APP_PATH/Contents/MacOS/AutonomousAIChat"
cp "$PWD/Resources/AppIcon.icns" "$ASSEMBLED_APP_PATH/Contents/Resources/AppIcon.icns"
ditto --noextattr "$SPARKLE_FRAMEWORK" "$ASSEMBLED_APP_PATH/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$ASSEMBLED_APP_PATH/Contents/MacOS/AutonomousAIChat"

cat > "$ASSEMBLED_APP_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>de</string>
    <key>CFBundleExecutable</key>
    <string>AutonomousAIChat</string>
    <key>CFBundleIdentifier</key>
    <string>com.leon.autonomous-ai-chat</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleName</key>
    <string>Autonomer KI-Gruppenchat</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>18.1.0</string>
    <key>CFBundleVersion</key>
    <string>22</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/LeonTOfficial/AutonomousAIChat/main/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>XI4zReuhkT5oIylZw3eXkmtQArhooU4Q7fucZ8qndi8=</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUAutomaticallyUpdate</key>
    <true/>
    <key>SUEnableInstallerLauncherService</key>
    <true/>
    <key>SUEnableSystemProfiling</key>
    <false/>
    <key>SUScheduledCheckInterval</key>
    <integer>86400</integer>
    <key>SUShowReleaseNotes</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

xattr -cr "$ASSEMBLED_APP_PATH" 2>/dev/null || true
codesign --force --sign - --timestamp=none "$ASSEMBLED_APP_PATH"
codesign --verify --deep --strict --verbose=2 "$ASSEMBLED_APP_PATH"

mkdir -p "$BUILD_DIR"
rm -rf "$APP_PATH"
ditto --noextattr "$ASSEMBLED_APP_PATH" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "✅ App-Bundle wurde erstellt."
if [[ "${1:-}" == "--build-only" ]]; then
  echo "🧪 Build-only: App wurde erstellt, aber nicht geöffnet."
  exit 0
fi

echo "🚀 Starte die App …"
pkill -x AutonomousAIChat 2>/dev/null || true
sleep 0.4
open -n "$APP_PATH"
