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
    <string>1.0.8</string>
    <key>CFBundleVersion</key>
    <string>180</string>
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

# The following section replaces the old zipping logic
# and assumes the universal binary is the primary one to work with.
# It also corrects the path for the universal app to be named simply "$APP_NAME.app"
# for the lipo operations, as implied by the provided snippet.

# Move the universal app to the standard name for processing
mv "$APP_UNIVERSAL" "$BUILD_DIR/$APP_NAME.app"

cd "$BUILD_DIR"

echo -e "\n📦 Zipping applications..."

# 1. Apple Silicon (ARM64) Zip
if [ -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" ]; then
    lipo -extract arm64 "$APP_NAME.app/Contents/MacOS/$APP_NAME" -output "${APP_NAME}_arm64" 2>/dev/null
    if [ $? -eq 0 ]; then
        mv "$APP_NAME.app/Contents/MacOS/$APP_NAME" "${APP_NAME}_universal_temp"
        mv "${APP_NAME}_arm64" "$APP_NAME.app/Contents/MacOS/$APP_NAME"
        zip -qr "${APP_NAME}_v1.0.8_AppleSilicon.zip" "$APP_NAME.app"
        echo "✅ Created Apple Silicon build"
        
        # 2. Intel (x86_64) Zip
        lipo -extract x86_64 "${APP_NAME}_universal_temp" -output "${APP_NAME}_x86_64" 2>/dev/null
        if [ $? -eq 0 ]; then
            mv "${APP_NAME}_x86_64" "$APP_NAME.app/Contents/MacOS/$APP_NAME"
            zip -qr "${APP_NAME}_v1.0.8_Intel.zip" "$APP_NAME.app"
            echo "✅ Created Intel build"
        fi
        
        # 3. Universal Zip (Restore the fat binary)
        mv "${APP_NAME}_universal_temp" "$APP_NAME.app/Contents/MacOS/$APP_NAME"
        zip -qr "${APP_NAME}_v1.0.8_Universal.zip" "$APP_NAME.app"
    fi
fi

echo "✅ Build complete! ZIP packages are in the build/ directory."
