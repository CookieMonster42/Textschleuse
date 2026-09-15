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

## PR-FAQ

> Working-Backwards-Dokument: Die Pressemitteilung ist so geschrieben, als
> wäre das Produkt fertig und angekündigt. Die Zitate sind erfunden und
> stehen für Rollen, nicht für Personen.

### Pressemitteilung

#### KI nutzen, ohne Namen und Kontodaten preiszugeben

**Textschleuse ist eine Menüleisten-App für den Mac, die einen Text vor dem
Weg ins KI-Tool anonymisiert und die Antwort wieder zurückdreht — mit zwei
Tastenkürzeln, ohne dass etwas den Rechner verlässt.**

Wer eine Kundenmail, einen Aktenvermerk oder eine Beschwerde mit einem
KI-Tool bearbeiten will, steht vor einem Dilemma. Der Text ist voller Namen,
IBANs, Telefonnummern und Aktenzeichen. Genau das darf nicht an einen fremden
Server. Also anonymisiert man von Hand, vergisst die dritte Nennung des
Nachnamens, und übersetzt hinterher jedes „Person A" wieder zurück. Das
dauert länger als die Antwort der KI wert ist — und beim nächsten Text geht
es von vorn los.

Textschleuse nimmt diesen Umweg weg. Text kopieren, `⌃⌥⌘S` drücken: In der
Zwischenablage liegt derselbe Text, nur stehen statt „Thorben Nyström" und
„DE89 3704 …" Platzhalter wie `PERSON_3F9A1C7B2E4D6A0B5C` und `IBAN_…`. Den
fügt man ins KI-Tool ein. Die Antwort kopieren, `⌃⌥⌘R` drücken: Die echten
Namen sind wieder drin. Ein Popup zeigt vorher, was ersetzt wird — Grün ist
sicher erkannt, Rot ist eine Vermutung, die man mit einer Ziffer bestätigt
oder verwirft. Was man einmal bestätigt hat, merkt sich das Wörterbuch.

**Was Textschleuse kann**

- **Erkennt von selbst:** E-Mail-Adressen, IBAN, BIC, Kartennummern mit
  Prüfsumme, Telefonnummern, Geburtsdaten, Steuer-IDs. Zuschaltbar: Websites,
  Anschriften, Aktenzeichen, Kunden- und Vertragsnummern.
- **Vermutet großzügig:** Vornamen aus einer offenen Namensliste, das
  folgende großgeschriebene Wort als Nachname, Firmen an ihrer Rechtsform.
  Eine unbestätigte Vermutung wird trotzdem ersetzt — Klartext bleibt nie
  versehentlich stehen.
- **Lernt Schreibweisen:** „Thorben Nyström", „Herr Nyström" und „T. N." sind
  dieselbe Person und bekommen zusammengehörige Decknamen. Der Rückweg stellt
  jede Schreibweise wieder her, nicht nur die Hauptnennung.
- **Decknamen mit Seed:** Die Kennung hinter dem Kürzel wird aus einem
  geheimen Seed und dem Namen abgeleitet. Ohne Seed ist sie nicht ablesbar,
  mit Seed nachvollziehbar — wer denselben Seed hat, bekommt dieselben
  Decknamen und kann Texte zurückdrehen, sobald die Namen in seinem
  Wörterbuch stehen.
- **Bleibt auf dem Rechner:** Das Wörterbuch liegt verschlüsselt auf der
  Platte, der Schlüssel im Schlüsselbund. Es gibt keine Netzwerkverbindung.
- **Zwei Wege:** Kurzbefehle für alle, die schnell sein wollen; ein Fenster
  mit Umschalter Schützen / Zurückdrehen, Verlauf und Wörterbuch für alle,
  die lieber klicken. Alle Tasten stehen auf einem Blatt, das beim Start
  erscheint.

**So läuft es ab**

1. Text kopieren, `⌃⌥⌘S`. Das Popup zeigt die Fundstellen. Offene
   Vermutungen mit `1`–`5` bestätigen, `⌘⏎` kopiert den geschützten Text.
2. Im KI-Tool einfügen. Über dem Text steht ein Hinweis, die Platzhalter
   unverändert zu übernehmen.
3. Antwort kopieren, `⌃⌥⌘R`, einfügen. Fertig.

**Stimme aus dem Alltag** (Sachbearbeitung in einer Rechtsabteilung,
erfunden): „Vorher habe ich die KI für alles genutzt, was keine Namen
enthielt — also für fast nichts. Jetzt drücke ich zwei Tasten und die Mail
geht raus, ohne dass ich überlegen muss, was drinsteht."

**Stimme aus der Entwicklung** (erfunden): „Wir haben uns gegen ein Modell
entschieden, das Namen erkennt, und für Regeln, die man lesen kann. Wenn die
App etwas übersieht, siehst du es im Popup und markierst es. Wenn ein Modell
etwas übersieht, siehst du es nie."

**Verfügbarkeit:** Textschleuse ist kostenlos und quelloffen. Das DMG liegt
unter Releases, Voraussetzung ist macOS 14 oder neuer auf Apple Silicon.

### FAQ für Nutzer

**Geht irgendetwas ins Netz?**
Nein. Die App hat keine Netzwerkverbindung. Erkennung, Wörterbuch und Rückweg
laufen auf dem Rechner. Ins KI-Tool kommt nur, was du selbst dort einfügst —
und das ist der geschützte Text.

**Was, wenn die App einen Namen übersieht?**
Im Popup markierst du ihn und drückst eine Ziffer. Ab dann kennt ihn das
Wörterbuch. Vermutungen, die du nicht anschaust, werden als
`UNBEKANNT_…` ersetzt, nicht als Klartext stehen gelassen. Der Rückweg meldet
sie, und mit dem Seed gehen sie auf, sobald der Name später gemerkt wird.

**Versteht die KI die Platzhalter?**
Über dem geschützten Text steht ein Hinweis, dass `PERSON_…`, `FIRMA_…` und
`IBAN_…` Platzhalter sind und unverändert übernommen werden sollen. Modelle
formatieren sie trotzdem gern um — `**PERSON 3F9A…**` oder `Person_3f9a…`.
Der Rückweg erkennt diese Schreibvarianten.

**Was ist der Seed, und wem gebe ich ihn?**
Der Seed ist ein Geheimnis im Wörterbuch. Aus ihm und dem Namen entsteht der
Deckname. Wer den Seed hat und den Namen kennt, weiß, welcher Deckname
dazugehört; wer ihn nicht hat, sieht nur Zufall. Teile ihn mit Kollegen, die
deine geschützten Texte lesen und zurückdrehen sollen — und behandle ihn wie
ein Passwort. Aus dem Deckname allein lässt sich der Name auch mit Seed nicht
errechnen; man braucht ihn im eigenen Wörterbuch.

**Können mehrere Leute zusammenarbeiten?**
Ja, über den Seed. Zwei Wörterbücher mit demselben Seed vergeben für
denselben Namen denselben Deckname. Jeder pflegt sein eigenes Wörterbuch; ein
Text vom Kollegen dreht sich zurück, sobald die Namen darin auch bei dir
stehen.

**Was passiert bei einem Rechnerwechsel?**
Das Wörterbuch ist mit einem Schlüssel aus dem Schlüsselbund verschlüsselt.
Ohne diesen Schlüssel ist es nicht lesbar. Deshalb fordert die App beim
ersten Speichern zu einem Klartext-Export auf. Der Export enthält echte Namen
und den Seed — die App sagt das beim Export deutlich.

**Funktioniert es mit formatierten Mails aus Outlook?**
Der Text wird zu reinem Text. Formatierung geht verloren, der Inhalt nicht.

**Für welche Sprache ist die Erkennung gemacht?**
Für deutsche Texte: Vornamen aus offenen Verwaltungsdaten, deutsche
Rechtsformen, deutsche Adress- und Aktenzeichenmuster. E-Mail, IBAN und
Telefon sind sprachunabhängig.

### FAQ intern: Entscheidungen, Technik, Risiken

**Warum Regeln und Listen statt eines Modells, das Namen erkennt?**
Weil man Regeln lesen kann. Ein Modell übersieht Namen still; eine Regel
übersieht sie nachvollziehbar, und das Popup zeigt jede Entscheidung. Dazu
kommt: Regeln laufen offline, deterministisch und in Millisekunden. Der
Preis ist eine bewusst großzügige Heuristik — im Zweifel vermutet die App
lieber einen Namen zu viel als einen zu wenig, und der Nutzer verwirft.

**Warum werden Decknamen aus einem Seed abgeleitet statt gezählt?**
`PERSON_47` verriet, dass es mindestens 46 andere gibt und wer zuerst kam.
Eine Zufallskennung verrät nichts, ist aber nur mit dem eigenen Wörterbuch
zu deuten. Die Ableitung aus Seed und Name (HMAC-SHA256, 18 Stellen)
verbindet beides: nicht ablesbar ohne Seed, stabil und teilbar mit Seed. Der
Seed liegt im verschlüsselten Wörterbuch. Alte Dateien mit Nummern bleiben
lesbar; verschickte Texte gehen weiter auf.

**Was ist das Sicherheitsmodell?**
Das Wörterbuch ist mit AES-GCM verschlüsselt, der Schlüssel liegt im
Schlüsselbund und wird ad-hoc-signiert an die App gebunden. Texte werden nie
gespeichert; der Sitzungsverlauf lebt im Arbeitsspeicher. Der Klartext-Export
ist absichtlich unverschlüsselt, damit ein Rechnerwechsel nicht zum
Totalverlust wird — die App warnt davor. Der Seed ist das zweite Geheimnis:
mit ihm lassen sich Decknamen für bekannte Namen nachrechnen, nicht mehr.

**Warum kein automatisches Einfügen in das KI-Tool?**
Dafür müsste die App Tastendrücke simulieren und dafür die
Bedienungshilfen-Berechtigung haben — ein weitreichender Zugriff für einen
kleinen Komfortgewinn. Die globalen Kurzbefehle laufen über Carbon
`RegisterEventHotKey` und kommen ohne diese Berechtigung aus.

**Warum ist die App nicht notarisiert?**
Es gibt kein Apple-Entwicklerkonto dafür. macOS blockiert den ersten
Doppelklick; der Rechtsklick-Weg „Öffnen" ist Apples vorgesehene Ausnahme und
einmalig. Das ist ein Hindernis für die Verbreitung, kein Sicherheitsrisiko
— die App ist ad-hoc signiert, und der Quellcode liegt offen.

**Welche Risiken bleiben?**
- Die Heuristik kennt keine Nachnamen ohne erkennbaren Vornamen davor und
  keine Namen in Kleinschreibung. Der Nutzer muss das Popup lesen.
- Ein KI-Tool kann einen Platzhalter so verstümmeln, dass der Rückweg ihn
  nicht mehr erkennt. Dann bleibt er stehen und wird gemeldet.
- Wer den Seed und den Export weitergibt, gibt alles weiter.
- Ohne Xcode, nur mit den Command Line Tools gebaut: Kein XCTest, die
  Prüfungen laufen als eigenes Programm (`swift run Pruefungen`) und als
  Selbsttest im Bundle. Das reicht, ist aber ungewöhnlich.

**Was ist bewusst nicht drin?**
Kein Verlauf auf der Platte, keine Cloud, kein Windows, keine automatische
Tastatureingabe, kein Import aus anderen Werkzeugen. Jedes davon würde die
einfache Zusicherung „nichts verlässt den Rechner" verwässern.
