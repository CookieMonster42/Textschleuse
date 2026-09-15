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
VERSION="0.4"

echo "→ Prüfungen"
swift run --configuration "$KONFIGURATION" Pruefungen

echo "→ Übersetzen"
swift build --configuration "$KONFIGURATION" --product Textschleuse

echo "→ Symbol"
if [[ ! -f ".build/Textschleuse.icns" ]] || [[ Werkzeug/Logo.swift -nt ".build/Textschleuse.icns" ]]; then
    swift Werkzeug/Logo.swift ".build/Textschleuse.icns" | sed 's/^/   /'
else
    echo "   unverändert"
fi

echo "→ Bundle bauen"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp ".build/$KONFIGURATION/Textschleuse" "$BUNDLE/Contents/MacOS/Textschleuse"
cp ".build/Textschleuse.icns" "$BUNDLE/Contents/Resources/Textschleuse.icns"

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Textschleuse</string>
    <key>CFBundleDisplayName</key>       <string>Textschleuse</string>
    <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>        <string>Textschleuse</string>
    <key>CFBundleIconFile</key>          <string>Textschleuse</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <!-- Kein Dock-Icon, kein Programmmenü. Die App lebt in der Menüleiste. -->
    <!-- Kein LSUIElement mehr: die App hat ein Fenster und ein Dock-Symbol.
         Wer nur die Menüleiste will, stellt das in den Einstellungen um;
         dann setzt die App die Aktivierungsart zur Laufzeit. -->
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

if [[ "${1:-}" == "--dmg" ]]; then
    echo "→ DMG bauen"
    BUEHNE=".build/dmg-buehne"
    rm -rf "$BUEHNE" ".build/Textschleuse-$VERSION.dmg"
    mkdir -p "$BUEHNE"
    cp -R "$BUNDLE" "$BUEHNE/Textschleuse.app"
    # Verknüpfung, damit man die App im Fenster nach rechts ziehen kann.
    ln -s /Applications "$BUEHNE/Programme"

    cat > "$BUEHNE/Bitte lesen.txt" <<'HINWEIS'
Textschleuse — Installation

1. Textschleuse.app auf "Programme" ziehen.
2. Beim ersten Start: rechte Maustaste auf die App, dann "Öffnen".
   Danach im Dialog noch einmal "Öffnen" bestätigen.

Warum der Umweg beim ersten Start?

Die App ist nicht bei Apple registriert (keine Notarisierung). macOS
blockiert sie deshalb beim Doppelklick. Der Rechtsklick-Weg ist die von
Apple vorgesehene Ausnahme und ist nur einmal nötig.

Was die App macht

Text aus der Zwischenablage nehmen, Namen und Bankdaten durch
Platzhalter ersetzen, Ergebnis zurück in die Zwischenablage. Die
Rückrichtung genauso. Alles bleibt auf diesem Rechner, es geht nichts
ins Netz.

Kurzbefehle
  ctrl-alt-cmd-S   Text schützen
  ctrl-alt-cmd-R   Platzhalter zurückdrehen

Prüfen, ob alles läuft

  /Applications/Textschleuse.app/Contents/MacOS/Textschleuse --selbsttest

risiq intern
HINWEIS

    hdiutil create \
        -volname "Textschleuse $VERSION" \
        -srcfolder "$BUEHNE" \
        -ov -format UDZO -quiet \
        ".build/Textschleuse-$VERSION.dmg"
    rm -rf "$BUEHNE"
    echo "   $PWD/.build/Textschleuse-$VERSION.dmg"
    echo "   $(du -h ".build/Textschleuse-$VERSION.dmg" | cut -f1)"
elif [[ "${1:-}" == "--install" ]]; then
    # ~/Applications statt /Applications: dort braucht es keine
    # Administratorrechte, und Launchpad und Spotlight finden es genauso.
    # Wer es systemweit will, kopiert von Hand mit sudo.
    ZIEL="$HOME/Applications"
    mkdir -p "$ZIEL"
    echo "→ Nach $ZIEL kopieren"
    rm -rf "$ZIEL/Textschleuse.app"
    cp -R "$BUNDLE" "$ZIEL/Textschleuse.app"
    echo "   $ZIEL/Textschleuse.app"
else
    echo "   $PWD/$BUNDLE"
fi
