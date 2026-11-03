#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
OUTPUT_DIR="$ROOT_DIR/outputs"
APP_DIR="$OUTPUT_DIR/Aura Protect.app"

cd "$ROOT_DIR"
# Build each architecture explicitly; keep the shipped app universal.
for ARCH in arm64 x86_64; do
    swift build --disable-sandbox -c release --arch "$ARCH" "$@"
    BIN_DIR="$(swift build --disable-sandbox -c release --arch "$ARCH" --show-bin-path "$@")"
    cp "$BIN_DIR/ClamAVDesk" "$ROOT_DIR/.build/AuraProtect-$ARCH"
done
if [[ -d "$APP_DIR" && "$APP_DIR" == "$OUTPUT_DIR/Aura Protect.app" ]]; then
    rm -rf "$APP_DIR"
fi
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
lipo -create "$ROOT_DIR/.build/AuraProtect-arm64" "$ROOT_DIR/.build/AuraProtect-x86_64" \
    -output "$APP_DIR/Contents/MacOS/ClamAVDesk"
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
plutil -insert CFBundleShortVersionString -string 1.2.1 "$APP_DIR/Contents/Info.plist"
plutil -insert LSMinimumSystemVersion -string 14.0 "$APP_DIR/Contents/Info.plist"
plutil -insert NSHighResolutionCapable -bool true "$APP_DIR/Contents/Info.plist"
plutil -insert NSServices -json '[{"NSMenuItem":{"default":"Scan with Aura Protect"},"NSMessage":"scanWithAura","NSPortName":"Aura Protect","NSSendTypes":["public.file-url"],"NSRequiredContext":{}}]' "$APP_DIR/Contents/Info.plist"
plutil -insert CFBundleDocumentTypes -json '[{"CFBundleTypeName":"Files and folders","CFBundleTypeRole":"Viewer","LSHandlerRank":"Alternate","LSItemContentTypes":["public.data","public.directory"]}]' "$APP_DIR/Contents/Info.plist"
codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
