#!/bin/bash
# Baut Textschleuse.app. Kein Xcode nötig, die Command Line Tools reichen.
#
#   ./bauen.sh            baut nach .build/Textschleuse.app
#   ./bauen.sh --install  baut und legt die App in ~/Applications ab
#   ./bauen.sh --dmg      baut dazu Textschleuse-$VERSION.dmg und Textschleuse.dmg
#   ./bauen.sh --release  baut die DMGs und legt das GitHub-Release v$VERSION an
#                         (oder lädt die DMGs an ein vorhandenes nach)
#
set -euo pipefail
cd "$(dirname "$0")"

KONFIGURATION=release
BUNDLE=".build/Textschleuse.app"
BUNDLE_ID="io.github.cookiemonster42.textschleuse"

# Signatur. Liegt ein „Developer ID Application"-Zertifikat im Schlüsselbund,
# wird damit signiert (Hardened Runtime, Zeitstempel) und die App samt DMG
# bei Apple notarisiert — danach öffnet macOS sie per Doppelklick, ohne den
# Rechtsklick-Umweg. Ohne Zertifikat bleibt es bei der Ad-hoc-Signatur.
#   SIGNIERUNG="Developer ID Application: Name (TEAMID)"   erzwingt eine Identität
#   NOTAR_PROFIL=textschleuse                              Profil aus
#       xcrun notarytool store-credentials textschleuse --apple-id … --team-id …
# Getrennt zugewiesen, nicht in einem String verschachtelt: bash 3.2 von
# macOS verschluckt sich an Anführungszeichen in einer Befehlssubstitution
# innerhalb von Anführungszeichen.
if [[ -z "${SIGNIERUNG:-}" ]]; then
    SIGNIERUNG=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')
fi
NOTAR_PROFIL="${NOTAR_PROFIL:-textschleuse}"
NOTARISIEREN=false
if [[ "$SIGNIERUNG" == Developer\ ID\ Application* ]]; then
    if security find-generic-password -s "com.apple.gke.notary.tool" -a "$NOTAR_PROFIL" >/dev/null 2>&1; then
        NOTARISIEREN=true
    else
        echo "Hinweis: Developer-ID-Zertifikat da, aber kein notarytool-Profil „$NOTAR_PROFIL"."
        echo "         Einrichten mit: xcrun notarytool store-credentials $NOTAR_PROFIL --apple-id <Apple-ID> --team-id <TEAMID>"
        echo "         Es wird signiert, aber nicht notarisiert."
    fi
fi

# Reicht eine Datei bei Apple ein und wartet auf das Urteil. Dauert meist ein
# bis fünf Minuten. Bei Ablehnung steht das Protokoll im Terminal.
notarisiere() {
    echo "   Notarisierung: $(basename "$1") wird bei Apple eingereicht …"
    local ausgabe
    ausgabe=$(xcrun notarytool submit "$1" --keychain-profile "$NOTAR_PROFIL" --wait --timeout 30m 2>&1) || true
    echo "$ausgabe" | sed 's/^/   /'
    if ! echo "$ausgabe" | grep -q "status: Accepted"; then
        local kennung
        kennung=$(echo "$ausgabe" | grep -o 'id: [0-9a-f-]*' | head -1 | cut -d' ' -f2)
        [[ -n "$kennung" ]] && xcrun notarytool log "$kennung" --keychain-profile "$NOTAR_PROFIL" | sed 's/^/   /'
        echo "✗ Notarisierung abgelehnt"
        exit 1
    fi
}
VERSION="0.6.2"

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
    <key>NSHumanReadableCopyright</key>  <string>Quelloffen, ohne Gewähr</string>
</dict>
</plist>
PLIST

echo "→ Signieren"
if [[ -n "$SIGNIERUNG" ]]; then
    # Hardened Runtime und Zeitstempel verlangt die Notarisierung. Die App
    # braucht keine Ausnahmen: kein JIT, keine fremden Bibliotheken.
    echo "   mit: $SIGNIERUNG"
    codesign --force --options runtime --timestamp \
        --sign "$SIGNIERUNG" --identifier "$BUNDLE_ID" "$BUNDLE"
else
    # Ad-hoc-Signatur. Ohne sie verweigert die Keychain den Zugriff auf den
    # Schlüssel, und macOS fragt bei jedem Start neu nach der Berechtigung
    # für die globalen Tastenkürzel.
    echo "   ad hoc (kein Developer-ID-Zertifikat im Schlüsselbund)"
    codesign --force --sign - --identifier "$BUNDLE_ID" "$BUNDLE"
fi
codesign --verify --strict --verbose "$BUNDLE" 2>&1 | sed 's/^/   /'

if [[ "$NOTARISIEREN" == true ]]; then
    echo "→ App notarisieren"
    # Als Zip einreichen, danach das Ticket an die App heften. So öffnet sie
    # auch dann, wenn der Rechner beim ersten Start gerade offline ist.
    rm -f ".build/Textschleuse.zip"
    ditto -c -k --keepParent "$BUNDLE" ".build/Textschleuse.zip"
    notarisiere ".build/Textschleuse.zip"
    xcrun stapler staple "$BUNDLE" | sed 's/^/   /'
    spctl --assess --type execute --verbose=2 "$BUNDLE" 2>&1 | sed 's/^/   /'
fi

if [[ "${1:-}" == "--dmg" || "${1:-}" == "--release" ]]; then
    echo "→ DMG bauen"
    BUEHNE=".build/dmg-buehne"
    rm -rf "$BUEHNE" ".build/Textschleuse-$VERSION.dmg" ".build/Textschleuse.dmg"
    mkdir -p "$BUEHNE"
    cp -R "$BUNDLE" "$BUEHNE/Textschleuse.app"
    # Verknüpfung, damit man die App im Fenster nach rechts ziehen kann.
    ln -s /Applications "$BUEHNE/Programme"

    if [[ "$NOTARISIEREN" == true ]]; then
        OEFFNEN_HINWEIS='1. Textschleuse.app auf "Programme" ziehen.
2. Doppelklick. Die App ist signiert und bei Apple notarisiert.'
    else
        OEFFNEN_HINWEIS='1. Textschleuse.app auf "Programme" ziehen.
2. Doppelklick. macOS meldet, die App könne nicht geöffnet werden.
   Die Meldung mit "Fertig" schließen.
3. Systemeinstellungen > Datenschutz & Sicherheit öffnen, nach unten
   rollen: dort steht "Textschleuse wurde blockiert" mit dem Knopf
   "Dennoch öffnen". Klicken, bestätigen. Das ist nur einmal nötig.
   (Bis macOS 14 reicht stattdessen Rechtsklick auf die App > "Öffnen".)

Warum der Umweg beim ersten Start?

Diese Ausgabe ist nicht bei Apple notarisiert. macOS lässt eine
heruntergeladene App ohne Notarisierung nur über diesen Weg zu.'
    fi
    cat > "$BUEHNE/Bitte lesen.txt" <<HINWEIS
Textschleuse — Installation

$OEFFNEN_HINWEIS

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

Quelloffen, privat entwickelt, ohne Gewähr.
HINWEIS

    hdiutil create \
        -volname "Textschleuse $VERSION" \
        -srcfolder "$BUEHNE" \
        -ov -format UDZO -quiet \
        ".build/Textschleuse-$VERSION.dmg"
    rm -rf "$BUEHNE"

    if [[ "$NOTARISIEREN" == true ]]; then
        echo "→ DMG signieren und notarisieren"
        # Auch das Abbild selbst: ein heruntergeladenes DMG prüft macOS
        # eigenständig, nicht nur die App darin.
        codesign --force --timestamp --sign "$SIGNIERUNG" ".build/Textschleuse-$VERSION.dmg"
        notarisiere ".build/Textschleuse-$VERSION.dmg"
        xcrun stapler staple ".build/Textschleuse-$VERSION.dmg" | sed 's/^/   /'
        spctl --assess --type open --context context:primary-signature --verbose=2 \
            ".build/Textschleuse-$VERSION.dmg" 2>&1 | sed 's/^/   /'
    fi
    # Dieselbe Datei noch einmal ohne Versionsnummer: unter diesem festen
    # Namen zeigt .../releases/latest/download/Textschleuse.dmg immer auf
    # die aktuelle Version. Die Website verlinkt genau darauf — der Name
    # muss so bleiben.
    cp ".build/Textschleuse-$VERSION.dmg" ".build/Textschleuse.dmg"
    echo "   $PWD/.build/Textschleuse-$VERSION.dmg"
    echo "   $PWD/.build/Textschleuse.dmg"
    echo "   $(du -h ".build/Textschleuse-$VERSION.dmg" | cut -f1)"

    if [[ "${1:-}" == "--release" ]]; then
        echo "→ Release v$VERSION"
        command -v gh >/dev/null || { echo "   gh fehlt (brew install gh)"; exit 1; }
        DATEIEN=(".build/Textschleuse-$VERSION.dmg" ".build/Textschleuse.dmg")
        if gh release view "v$VERSION" >/dev/null 2>&1; then
            # Gibt es das Release schon, werden nur die Dateien ersetzt.
            gh release upload "v$VERSION" "${DATEIEN[@]}" --clobber
            echo "   Dateien an v$VERSION nachgeladen"
        else
            # Notizen aus einer Datei, wenn RELEASE_NOTIZEN darauf zeigt;
            # sonst erzeugt GitHub sie aus den Pull Requests.
            if [[ -n "${RELEASE_NOTIZEN:-}" && -f "$RELEASE_NOTIZEN" ]]; then
                NOTIZEN=(--notes-file "$RELEASE_NOTIZEN")
            else
                NOTIZEN=(--generate-notes)
            fi
            gh release create "v$VERSION" "${DATEIEN[@]}" \
                --target main --title "Textschleuse $VERSION" "${NOTIZEN[@]}"
        fi
        gh release view "v$VERSION" --json url --jq '.url' | sed 's/^/   /'
        echo "   Direktlink: https://github.com/CookieMonster42/Textschleuse/releases/latest/download/Textschleuse.dmg"
    fi
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
