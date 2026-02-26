#!/bin/bash
set -e

APP_NAME="Mino"
BUILD_DIR="build"

echo "🧹 Cleaning previous build..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

function create_app_structure() {
    local APP_PATH="$1"
    local CONTENTS_DIR="$APP_PATH/Contents"
    local MACOS_DIR="$CONTENTS_DIR/MacOS"
    local RESOURCES_DIR="$CONTENTS_DIR/Resources"

    mkdir -p "$MACOS_DIR"
    mkdir -p "$RESOURCES_DIR"

    cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.nad.mino</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.7</string>
    <key>CFBundleVersion</key>
    <string>179</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <string>1</string>
</dict>
</plist>
EOF

    if [ -f "../icon.icns" ]; then
        cp "../icon.icns" "$RESOURCES_DIR/AppIcon.icns"
    fi
}

APP_ARM64="$BUILD_DIR/${APP_NAME}_AppleSilicon.app"
APP_X86_64="$BUILD_DIR/${APP_NAME}_Intel.app"
APP_UNIVERSAL="$BUILD_DIR/${APP_NAME}_Universal.app"

echo "📝 Creating App Structures..."
create_app_structure "$APP_ARM64"
create_app_structure "$APP_X86_64"
create_app_structure "$APP_UNIVERSAL"

echo "🔨 Compiling Swift sources for ARM64 (Apple Silicon)..."
swiftc -Osize -parse-as-library Sources/*.swift -target arm64-apple-macosx12.0 -o "$APP_ARM64/Contents/MacOS/$APP_NAME"

echo "🔨 Compiling Swift sources for x86_64 (Intel)..."
swiftc -Osize -parse-as-library Sources/*.swift -target x86_64-apple-macosx12.0 -o "$APP_X86_64/Contents/MacOS/$APP_NAME"

echo "🔗 Creating Universal Binary..."
lipo -create -output "$APP_UNIVERSAL/Contents/MacOS/$APP_NAME" "$APP_ARM64/Contents/MacOS/$APP_NAME" "$APP_X86_64/Contents/MacOS/$APP_NAME"

echo "📦 Zipping packages..."
cd "$BUILD_DIR"

# Zip Apple Silicon build
mv "${APP_NAME}_AppleSilicon.app" "$APP_NAME.app"
zip -qr "${APP_NAME}_v1.0.7_AppleSilicon.zip" "$APP_NAME.app"
mv "$APP_NAME.app" "${APP_NAME}_AppleSilicon.app"

# Zip Intel build
mv "${APP_NAME}_Intel.app" "$APP_NAME.app"
zip -qr "${APP_NAME}_v1.0.7_Intel.zip" "$APP_NAME.app"
mv "$APP_NAME.app" "${APP_NAME}_Intel.app"

# Zip Universal build
mv "${APP_NAME}_Universal.app" "$APP_NAME.app"
zip -qr "${APP_NAME}_v1.0.7_Universal.zip" "$APP_NAME.app"

echo "✅ Build complete! ZIP packages are in the build/ directory."
