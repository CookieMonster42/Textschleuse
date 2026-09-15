# Textschleuse

Ersetzt Namen, Adressen und Bankdaten durch Platzhalter, bevor ein Text in
ein KI-Tool geht — und dreht die Antwort wieder zurück. Läuft komplett auf
dem eigenen Mac, es geht nichts ins Netz.

Aus `Sehr geehrter Herr Nyström, Ihre IBAN DE89 … stimmt.` wird
`Sehr geehrter Herr PERSON_3F9A1C7B2E4D6A0B5C, Ihre IBAN IBAN_A41C… stimmt.`
Die Kennung hinter dem Kürzel wird aus einem geheimen Seed und dem Namen
abgeleitet. Ohne den Seed sieht sie aus wie Zufall — weder Anzahl noch
Reihenfolge der Einträge lassen sich ablesen, und aus der Kennung nicht der
Name. Mit dem Seed ist sie nachvollziehbar: wer denselben Seed hat, bekommt
für denselben Namen denselben Deckname und kann einen Text zurückdrehen,
sobald der Name in seinem Wörterbuch steht. Der Seed steht in den
Einstellungen und liegt mit dem Wörterbuch verschlüsselt auf dem Rechner.
Kommt die Antwort zurück, werden die Platzhalter wieder zu den echten Namen.

## Herunterladen

Die fertige App liegt unter **Releases** rechts auf dieser Seite als
`Textschleuse-<Version>.dmg`. Voraussetzung: macOS 14 oder neuer auf Apple
Silicon.

1. DMG öffnen, `Textschleuse.app` auf „Programme" ziehen.
2. Beim ersten Start: rechte Maustaste auf die App, dann „Öffnen", und im
   Dialog noch einmal „Öffnen" bestätigen. Das ist nur einmal nötig — die App
   ist nicht bei Apple notarisiert, deshalb blockiert macOS den Doppelklick.
3. Die App zeigt ein Fenster und ein Symbol in der Menüleiste. Kurzbefehle:
   `⌃⌥⌘S` schützt die Zwischenablage, `⌃⌥⌘R` dreht sie zurück.

## Bedienung in Kürze

Text kopieren, `⌃⌥⌘S` drücken. Das Popup zeigt jede Fundstelle: Grün ist
sicher erkannt (IBAN, E-Mail, Telefon, Wörterbuch), Rot ist eine Vermutung.
Mit `1`–`5` wird eine markierte Stelle als Person, Firma, Ort, Nummer oder
Sonstiges geschützt; zugeschaltete Erkennungen wie Website oder Aktenzeichen
bekommen die Ziffern dahinter. `⌘⏎` legt den geschützten Text in die
Zwischenablage.

Die Antwort des KI-Tools kopieren, `⌃⌥⌘R` drücken, einfügen.

Wer lieber im Fenster arbeitet: ein Textfeld, oben der Umschalter zwischen
Schützen und Zurückdrehen. Der Text bleibt beim Umschalten stehen und wird in
der anderen Richtung geprüft; jede Richtung hat ihren eigenen Verlauf. Der
Text lässt sich bearbeiten wie überall — tippen, alles markieren, löschen.

Alle Tasten stehen auf einem Blatt, das beim Start erscheint und jederzeit
über den Knopf „Tastenkürzel" oder `⌘/` zu haben ist.

## Selbst bauen

Es braucht nur die Command Line Tools, kein Xcode.

```bash
./bauen.sh            # baut .build/Textschleuse.app, mit Prüfungen
./bauen.sh --install  # legt die App zusätzlich in ~/Applications ab
./bauen.sh --dmg      # baut das DMG zum Weitergeben
```

Prüfen, ob auf einem Rechner alles läuft:

```bash
/Applications/Textschleuse.app/Contents/MacOS/Textschleuse --selbsttest
```

Die Spezifikation steht in [SPEC.md](SPEC.md).
