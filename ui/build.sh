#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_NAME="Chronoframe"
BUILD_DIR="${SCRIPT_DIR}/build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RESOURCES_DIR="${APP_DIR}/Contents/Resources"
BACKEND_DIR="${RESOURCES_DIR}/Backend"
EXECUTABLE_PATH="${SCRIPT_DIR}/.build/debug/${APP_NAME}App"
ICON_SOURCE="${SCRIPT_DIR}/Resources/AppIcon.icns"
TMP_DIR="${TMPDIR:-/tmp}/chronoframe-ui-build"
MODULE_CACHE_DIR="${TMP_DIR}/module-cache"
SPM_CACHE_DIR="${TMP_DIR}/spm-cache"
SPM_CONFIG_DIR="${TMP_DIR}/spm-config"
SPM_SECURITY_DIR="${TMP_DIR}/spm-security"

mkdir -p "$BUILD_DIR" "$MACOS_DIR" "$RESOURCES_DIR" "$BACKEND_DIR" \
  "$MODULE_CACHE_DIR" "$SPM_CACHE_DIR" "$SPM_CONFIG_DIR" "$SPM_SECURITY_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$BACKEND_DIR"

echo "🔨 Building Swift package from ${SCRIPT_DIR}..."
(
  cd "$SCRIPT_DIR"
  env CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" \
      SWIFT_MODULECACHE_PATH="$MODULE_CACHE_DIR" \
      swift build \
      --product "${APP_NAME}App" \
      --disable-sandbox \
      --cache-path "$SPM_CACHE_DIR" \
      --config-path "$SPM_CONFIG_DIR" \
      --security-path "$SPM_SECURITY_DIR"
)

if [ ! -f "$EXECUTABLE_PATH" ]; then
  echo "error: expected executable at $EXECUTABLE_PATH" >&2
  exit 1
fi

echo "📦 Staging app bundle..."
cp "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
cp "$REPO_ROOT/chronoframe.py" "$BACKEND_DIR/"
cp -R "$REPO_ROOT/chronoframe" "$BACKEND_DIR/"
cp "$REPO_ROOT/requirements.txt" "$BACKEND_DIR/"
find "$BACKEND_DIR/chronoframe" -type d -name "__pycache__" -prune -exec rm -rf {} +

if [ -f "$ICON_SOURCE" ]; then
  cp "$ICON_SOURCE" "${RESOURCES_DIR}/AppIcon.icns"
fi

echo "📝 Generating Info.plist..."
cat <<EOF > "${APP_DIR}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.nishith.chronoframe</string>
    <key>CFBundleDisplayName</key>
    <string>Chronoframe</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>3.0</string>
    <key>CFBundleVersion</key>
    <string>3</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

if [ -f "${RESOURCES_DIR}/AppIcon.icns" ]; then
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "${APP_DIR}/Contents/Info.plist" >/dev/null 2>&1 || true
fi

echo "✅ Build complete!"
echo "➡️  You can run it with: open \"${APP_DIR}\""
