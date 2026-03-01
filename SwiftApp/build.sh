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
    <string>1.2.5</string>
    <key>CFBundleVersion</key>
    <string>185</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <string>1</string>
</dict>
</plist>
EOF

    if [ -f "../icon.png" ]; then
        echo "🎨 Generating AppIcon.icns from icon.png..."
        ICONSET_DIR="/tmp/MinoIcon.iconset"
        mkdir -p "$ICONSET_DIR"
        sips -z 16 16 "../icon.png" --out "$ICONSET_DIR/icon_16x16.png" > /dev/null 2>&1
        sips -z 32 32 "../icon.png" --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null 2>&1
        sips -z 32 32 "../icon.png" --out "$ICONSET_DIR/icon_32x32.png" > /dev/null 2>&1
        sips -z 64 64 "../icon.png" --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null 2>&1
        sips -z 128 128 "../icon.png" --out "$ICONSET_DIR/icon_128x128.png" > /dev/null 2>&1
        sips -z 256 256 "../icon.png" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null 2>&1
        sips -z 256 256 "../icon.png" --out "$ICONSET_DIR/icon_256x256.png" > /dev/null 2>&1
        sips -z 512 512 "../icon.png" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null 2>&1
        sips -z 512 512 "../icon.png" --out "$ICONSET_DIR/icon_512x512.png" > /dev/null 2>&1
        sips -z 1024 1024 "../icon.png" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null 2>&1
        iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
        rm -rf "$ICONSET_DIR"
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
        zip -qr "${APP_NAME}_v1.2.5_AppleSilicon.zip" "$APP_NAME.app"
        echo "✅ Created Apple Silicon build"
        
        # 2. Intel (x86_64) Zip
        lipo -extract x86_64 "${APP_NAME}_universal_temp" -output "${APP_NAME}_x86_64" 2>/dev/null
        if [ $? -eq 0 ]; then
            mv "${APP_NAME}_x86_64" "$APP_NAME.app/Contents/MacOS/$APP_NAME"
            zip -qr "${APP_NAME}_v1.2.5_Intel.zip" "$APP_NAME.app"
            echo "✅ Created Intel build"
        fi
        
        # 3. Universal Zip (Restore the fat binary)
        mv "${APP_NAME}_universal_temp" "$APP_NAME.app/Contents/MacOS/$APP_NAME"
        zip -qr "${APP_NAME}_v1.2.5_Universal.zip" "$APP_NAME.app"
    fi
fi

echo "✅ Build complete! ZIP packages are in the build/ directory."

# --- Homebrew Cask Generation ---
VERSION="1.2.5"
echo -e "\n🍺 Generating Homebrew Cask formula (mino.rb)..."

SHA_ARM=$(shasum -a 256 "${APP_NAME}_v1.2.5_AppleSilicon.zip" | awk '{print $1}')
SHA_INTEL=$(shasum -a 256 "${APP_NAME}_v1.2.5_Intel.zip" | awk '{print $1}')

cat > "mino.rb" <<EOF
cask "mino" do
  version "${VERSION}"

  on_arm do
    sha256 "${SHA_ARM}"
    url "https://github.com/nad-bit/Mino/releases/download/v#{version}/Mino_v#{version}_AppleSilicon.zip"
  end

  on_intel do
    sha256 "${SHA_INTEL}"
    url "https://github.com/nad-bit/Mino/releases/download/v#{version}/Mino_v#{version}_Intel.zip"
  end

  name "Mino"
  desc "A lightweight, native macOS menu bar app to track GitHub releases"
  homepage "https://github.com/nad-bit/Mino"

  depends_on macos: ">= :monterey"

  app "Mino.app"
end
EOF

echo "✅ Generated mino.rb in build/ directory."
echo "⚠️  CRITICAL: When uploading to your tap repository, ensure this file is placed in a 'Casks' directory (i.e., Casks/mino.rb)"

# --- Auto-Push to Homebrew Tap ---
if [ "$1" == "--release" ]; then
    echo -e "\n☁️  Updating Homebrew Tap repository..."
    TAP_REPO="https://github.com/nad-bit/homebrew-tap.git"
    TAP_CLONE_DIR="/tmp/homebrew-tap-mino"
    
    rm -rf "$TAP_CLONE_DIR"
    # Clone via HTTPS which will use the system keychain / git credential manager
    git clone "$TAP_REPO" "$TAP_CLONE_DIR" 2>/dev/null || true
    
    if [ -d "$TAP_CLONE_DIR" ]; then
        mkdir -p "$TAP_CLONE_DIR/Casks"
        cp "mino.rb" "$TAP_CLONE_DIR/Casks/mino.rb"
        
        cd "$TAP_CLONE_DIR"
        
        # Check if there are any changes
        if ! git diff --quiet || ! git diff --staged --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
            git add Casks/mino.rb
            git commit -m "Update Mino to v${VERSION}" >/dev/null 2>&1
            
            echo "Pushing new Cask formula to GitHub..."
            if git push origin main 2>/dev/null; then
                echo "✅ Homebrew Tap updated successfully!"
            else
                echo "⚠️  Failed to push to Homebrew Tap. You may need to update the file manually."
            fi
        else
            echo "✅ Homebrew Tap is already up to date."
        fi
    else
         echo "⚠️  Could not clone Homebrew Tap. You may not have SSH access configured for this repo."
    fi
else
    echo -e "\n⏩ Skipping Homebrew Tap update. Use './build.sh --release' to push to the tap."
fi
