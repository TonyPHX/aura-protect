#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
OUTPUT_DIR="$ROOT_DIR/outputs"
APP_DIR="$OUTPUT_DIR/Aura Protect.app"

cd "$ROOT_DIR"
swift build --disable-sandbox -c release
if [[ -d "$APP_DIR" && "$APP_DIR" == "$OUTPUT_DIR/Aura Protect.app" ]]; then
    rm -rf "$APP_DIR"
fi
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp ".build/release/ClamAVDesk" "$APP_DIR/Contents/MacOS/ClamAVDesk"
cp -R "$ROOT_DIR/Vendor/ClamAV" "$APP_DIR/Contents/Resources/ClamAV"
cp "$ROOT_DIR/Assets/AuraProtectIcon.icns" "$APP_DIR/Contents/Resources/AuraProtectIcon.icns"
cp "$ROOT_DIR/Assets/AuraProtectIcon.png" "$APP_DIR/Contents/Resources/AuraProtectIcon.png"
cp "$ROOT_DIR/LICENSE" "$APP_DIR/Contents/Resources/AuraProtect-License.txt"
plutil -create xml1 "$APP_DIR/Contents/Info.plist"
plutil -insert CFBundleExecutable -string ClamAVDesk "$APP_DIR/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string com.local.AuraProtect "$APP_DIR/Contents/Info.plist"
plutil -insert CFBundleName -string "Aura Protect" "$APP_DIR/Contents/Info.plist"
plutil -insert CFBundleDisplayName -string "Aura Protect" "$APP_DIR/Contents/Info.plist"
plutil -insert CFBundleIconFile -string AuraProtectIcon.icns "$APP_DIR/Contents/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$APP_DIR/Contents/Info.plist"
plutil -insert CFBundleShortVersionString -string 1.1.4 "$APP_DIR/Contents/Info.plist"
plutil -insert LSMinimumSystemVersion -string 14.0 "$APP_DIR/Contents/Info.plist"
plutil -insert NSHighResolutionCapable -bool true "$APP_DIR/Contents/Info.plist"
codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
