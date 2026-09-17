#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
cd "$root"

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

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
  echo "Build succeeded but the app bundle was not found." >&2
  exit 1
fi

fix_and_sign() {
  local app="$1"
  plutil -replace CFBundleExecutable -string "Desktop Translator" "$app/Contents/Info.plist" >/dev/null
  xattr -cr "$app" >/dev/null 2>&1 || true
  local appex="$app/Contents/PlugIns/TranslatorWidget.appex"
  local widget_ent="$root/Sources/Widget/Widget.entitlements"
  local app_ent="$root/DesktopTranslator.entitlements"
  codesign --force --sign - --timestamp=none --identifier com.desktoptranslator.app.widget --entitlements "$widget_ent" "$appex/Contents/MacOS/TranslatorWidget"
  codesign --force --sign - --timestamp=none --identifier com.desktoptranslator.app.widget --entitlements "$widget_ent" "$appex"
  codesign --force --sign - --timestamp=none --identifier com.desktoptranslator.app --entitlements "$app_ent" "$app"
}

register_widget() {
  local appex="$1/Contents/PlugIns/TranslatorWidget.appex"
  pluginkit -a "$appex" >/dev/null 2>&1 || true
  pluginkit -e use -i com.desktoptranslator.app.widget >/dev/null 2>&1 || true
}

app="$root/Desktop Translator.app"
rm -rf "$app"
cp -R "$built" "$app"
fix_and_sign "$app"

for dest in "$HOME/Applications" "/Applications"; do
  mkdir -p "$dest"
  rm -rf "$dest/Desktop Translator.app"
  if cp -R "$app" "$dest/Desktop Translator.app" 2>/dev/null; then
    fix_and_sign "$dest/Desktop Translator.app"
    register_widget "$dest/Desktop Translator.app"
    echo "Installed to $dest/Desktop Translator.app"
  fi
done

rm -f "$HOME/Desktop/Desktop Translator.app" "$HOME/Desktop/桌面译.app"
launch_agent="$HOME/Library/LaunchAgents/com.desktoptranslator.app.plist"
launchctl bootout "gui/$(id -u)/com.desktoptranslator.app" >/dev/null 2>&1 || true
launchctl unload "$launch_agent" >/dev/null 2>&1 || true
rm -f "$launch_agent"
osascript -e 'tell application "System Events" to delete login item "Desktop Translator"' >/dev/null 2>&1 || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/Desktop Translator.app" >/dev/null 2>&1 || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Applications/Desktop Translator.app" >/dev/null 2>&1 || true

echo "Created $app"
