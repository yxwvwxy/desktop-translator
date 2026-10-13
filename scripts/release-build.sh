#!/usr/bin/env bash
# Builds a release .zip for GitHub Releases (no local install).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

swift "$root/generate-icon.swift" "$root"

xcodebuild \
  -project "DesktopTranslator.xcodeproj" \
  -scheme DesktopTranslator \
  -configuration Release \
  -derivedDataPath "$root/build" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  DEVELOPMENT_TEAM="" \
  build

built="$(find "$root/build/Build/Products/Release" -maxdepth 2 -name "Desktop Translator.app" -print -quit)"
if [[ -z "$built" ]]; then
  echo "Build succeeded but Desktop Translator.app was not found." >&2
  exit 1
fi

dist="$root/dist"
app="$dist/Desktop Translator.app"
zip_path="$dist/Desktop-Translator-macOS.zip"
rm -rf "$dist"
mkdir -p "$dist"
cp -R "$built" "$app"

plutil -replace CFBundleExecutable -string "Desktop Translator" "$app/Contents/Info.plist" >/dev/null
xattr -cr "$app" >/dev/null 2>&1 || true

widget_ent="$root/Sources/Widget/Widget.entitlements"
app_ent="$root/DesktopTranslator.entitlements"
appex="$app/Contents/PlugIns/TranslatorWidget.appex"
codesign --force --sign - --timestamp=none --identifier com.desktoptranslator.app.widget --entitlements "$widget_ent" "$appex/Contents/MacOS/TranslatorWidget"
codesign --force --sign - --timestamp=none --identifier com.desktoptranslator.app.widget --entitlements "$widget_ent" "$appex"
codesign --force --sign - --timestamp=none --identifier com.desktoptranslator.app --entitlements "$app_ent" "$app"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
zip_path="$dist/Desktop-Translator-${version}-macOS.zip"
rm -f "$zip_path"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip_path"

echo "Created $zip_path"
