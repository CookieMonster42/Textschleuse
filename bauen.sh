#!/bin/bash
# Baut Textschleuse.app. Kein Xcode nötig, die Command Line Tools reichen.
#
#   ./bauen.sh            baut nach .build/Textschleuse.app
#   ./bauen.sh --install  baut und legt die App in /Applications ab
#
set -euo pipefail
cd "$(dirname "$0")"

KONFIGURATION=release
BUNDLE=".build/Textschleuse.app"
BUNDLE_ID="de.risiq.textschleuse"
VERSION="0.1"

echo "→ Prüfungen"
swift run --configuration "$KONFIGURATION" Pruefungen

echo "→ Übersetzen"
swift build --configuration "$KONFIGURATION" --product Textschleuse

echo "→ Bundle bauen"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp ".build/$KONFIGURATION/Textschleuse" "$BUNDLE/Contents/MacOS/Textschleuse"

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Textschleuse</string>
    <key>CFBundleDisplayName</key>       <string>Textschleuse</string>
    <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>        <string>Textschleuse</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <!-- Kein Dock-Icon, kein Programmmenü. Die App lebt in der Menüleiste. -->
    <key>LSUIElement</key>               <true/>
    <key>NSHumanReadableCopyright</key>  <string>risiq intern</string>
</dict>
</plist>
PLIST

# Ad-hoc-Signatur. Ohne sie verweigert die Keychain den Zugriff auf den
# Schlüssel, und macOS fragt bei jedem Start neu nach der Berechtigung für
# die globalen Tastenkürzel.
echo "→ Signieren"
codesign --force --sign - --identifier "$BUNDLE_ID" "$BUNDLE"
codesign --verify --verbose "$BUNDLE" 2>&1 | sed 's/^/   /'

if [[ "${1:-}" == "--install" ]]; then
    echo "→ Nach /Applications kopieren"
    rm -rf "/Applications/Textschleuse.app"
    cp -R "$BUNDLE" "/Applications/Textschleuse.app"
    echo "   /Applications/Textschleuse.app"
else
    echo "   $PWD/$BUNDLE"
fi
