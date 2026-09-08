# Textschleuse für macOS — Spezifikation

Stand: 7. September 2026. Grundlage: Interview vom selben Tag, Vorlage ist der
bestehende Browser-Prototyp (Version 0.7).

## Zweck

Du kopierst einen Text, drückst einen Hotkey, und in der Zwischenablage liegt
derselbe Text mit Platzhaltern statt echter Namen, Adressen und Bankdaten. Den
fügst du in ein KI-Tool ein. Die Antwort kopierst du, drückst den zweiten
Hotkey, und die echten Namen sind zurück.

Die App läuft in der Menüleiste, ohne Dock-Icon, und arbeitet auch dann, wenn
ein anderes Programm im Vordergrund ist.

## Technik

Native Swift mit AppKit, gebaut über SwiftPM. Xcode ist auf dem Rechner nicht
installiert, deshalb entsteht das `.app`-Bundle über ein Build-Skript: Binary
nach `Contents/MacOS/`, `Info.plist` mit `LSUIElement = true`, danach ad-hoc
signiert. Zielsystem ist macOS 26.5 auf Apple Silicon.

Globale Hotkeys laufen über Carbon `RegisterEventHotKey`, weil das ohne
Accessibility-Berechtigung funktioniert. Ein technischer Vorabtest prüft, ob
Build, Bundle, Signierung und Hotkey-Registrierung in dieser Umgebung
tatsächlich durchlaufen.

Keine automatische Tastatureingabe: Die App schickt kein Cmd+V in die
Vordergrund-App. Du fügst selbst ein.

## Ablauf beim Schützen

Hotkey drücken, Popup öffnet sich in der Mitte des aktiven Bildschirms
(Position in den Einstellungen änderbar, Voreinstellung ist der Mauszeiger).
Das Popup zeigt den Text mit den Fundstellen als Inline-Chips: `Meier →
PERSON_1`. Passagen ohne Fundstellen sind zusammengefaltet. Bei kurzen Texten
stehen Original und Ergebnis untereinander, bei langen nebeneinander; das
Fenster wächst mit dem Inhalt bis maximal 70 Prozent der Bildschirmhöhe, danach
wird gescrollt. Oben steht ein Zähler: „12 von 40 geprüft".

Grün markierte Fundstellen sind Regeltreffer und brauchen keine Bestätigung.
Sie erscheinen zusammengefasst als aufklappbare Zeile („8 IBAN, 5 E-Mail, 2
Telefon — ersetzt"), nicht einzeln. Rot markierte sind Vermutungen und stehen
einzeln in der Liste.

Tastatur:

| Taste | Wirkung |
|---|---|
| Enter | ersetzen, in die Zwischenablage, Popup schließen |
| ⌘Enter | dasselbe, plus alle Unbekannten ins Wörterbuch übernehmen |
| Esc | abbrechen, Zwischenablage bleibt unverändert |
| ↑ / ↓ | zwischen Fundstellen springen |
| 1–5 | Typ setzen: Person, Firma, Ort, Nummer, Sonstiges |
| ⌫ | Fundstelle verwerfen |

Jede dieser Funktionen ist auch mit der Maus erreichbar. Wer klickt, bekommt
den zugehörigen Tastendruck eingeblendet.

Findet die App nichts, erscheint ein kleines Popup mit dem Hinweis, dass es
sich nach 1,5 Sekunden von selbst schließt. So weißt du, dass der Hotkey
angekommen ist.

Bei Texten ab etwa 100 KB zeigt das Popup einen Fortschrittsbalken, statt zu
blockieren.

## Was in der Zwischenablage landet

Über dem Text steht immer der Hinweis, die Platzhalter unverändert zu
übernehmen. Enthält der Text Unbekannte, kommt ein zweiter Block dazu, der sie
namentlich aufzählt. Beide Hinweise sind auf Deutsch.

Formatierter Text aus Mail oder Outlook wird zu reinem Text eingedampft.

## Erkennung

Ohne Nachfrage ersetzt (grün): E-Mail-Adressen, IBAN, BIC, Kreditkartennummern
mit Luhn-Prüfung, Geburtsdaten, Steuer-Identifikationsnummern, alles aus dem
Wörterbuch. Telefonnummern mit Ländervorwahl (+49, 0049) immer; ohne Vorwahl
nur bei einem Signalwort davor (Tel, Mobil, Fon, Durchwahl) oder typischer
Formatierung.

Als Vermutung vorgeschlagen (rot): Vornamen aus einer mitgelieferten Liste, das
darauf folgende großgeschriebene Wort als Nachname, Firmennamen an ihren
Rechtsformen (GmbH, eG, AG), großgeschriebene Wortpaare, Postanschriften, URLs
mit Namensbestandteilen, Treffer der Tippfehler-Toleranz. Im Zweifel vermutet
die App lieber, als eine Fundstelle zu übersehen.

Eine rote Fundstelle, die du nicht bestätigst, wird trotzdem ersetzt, nämlich
als `UNBEKANNT_n`. Klartext bleibt nie versehentlich stehen.

Treffer gelten nur für ganze Wörter. Groß- und Kleinschreibung spielt keine
Rolle. Mitgetroffen werden Genitiv- und Dativendungen, Umlautumschriften
(Nyström, Nystroem, Nystrom), Bindestrich statt Leerzeichen und Abkürzungen mit
Punkt („T. Nyström"). Beim Rückweg entsteht wieder die Originalform.

## Platzhalter und Aliasgruppen

Platzhalter sind deutsch: `PERSON_1`, `FIRMA_1`, `ORT_1`, `NUMMER_1`,
`BEGRIFF_1`, `UNBEKANNT_1`.

Ein gemerkter Begriff behält seine Nummer dauerhaft. Löschst du einen Eintrag,
wird die Nummer nie wieder vergeben, damit bereits verschickte Texte eindeutig
bleiben.

Dieselbe Person taucht in einem Text unterschiedlich auf. „Thorben Nyström"
wird `PERSON_7`, „Herr Nyström" wird `PERSON_7B`, „T. N." wird `PERSON_7C`.
Jeder Alias löst beim Rückweg in seine eigene Schreibweise auf, nicht in die
Hauptnennung. So bleiben zwei Personen desselben Typs auseinanderzuhalten.
Passt ein neuer Fund zum Nachnamen einer bekannten Person, schlägt das Popup
die Zuordnung vor; du bestätigst oder lehnst sie mit einem Tastendruck ab.

## Rückweg

Zweiter Hotkey, gleiches Fenster, umgekehrte Richtung. Auflösbare Platzhalter
sind grün, unbekannte rot. Unbekannte bleiben im Text stehen und werden im
Popup gemeldet; das Kopieren wird nicht blockiert.

## Wörterbuch

Gespeichert unter `~/Library/Application Support/de.risiq.textschleuse/`,
verschlüsselt, Schlüssel in der Keychain. Format ist JSON mit Schemaversion,
damit spätere Programmversionen alte Dateien migrieren können.

Regeltreffer wie IBAN oder E-Mail landen dauerhaft im Wörterbuch, aber in einer
eigenen Sektion „automatisch erkannt", die sich mit einem Klick leeren lässt.
Ohne das bricht der Rückweg, sobald du eine Mail einen Tag später beantwortest.

Beim ersten Speichern fordert die App einmalig zu einem Klartext-Export auf und
merkt sich den Pfad. Geht der Keychain-Eintrag verloren, etwa bei einem
Rechnerwechsel, ist das Wörterbuch ohne dieses Backup endgültig weg. Der Export
liegt unverschlüsselt auf der Platte und enthält echte Namen und Bankdaten —
die App sagt das beim Export deutlich.

Ein Import aus dem Browser-Prototyp ist nicht vorgesehen.

## Einstellungsfenster

Hotkeys werden durch Tastendruck aufgenommen, mit Prüfung gegen belegte
Systemkürzel. Voreinstellung: ⌃⌥⌘S zum Schützen, ⌃⌥⌘R für den Rückweg.

Der Wörterbuch-Editor listet die Einträge nach Entität gruppiert, Aliase
eingerückt darunter, mit Suchfeld. Einträge lassen sich per Drag & Drop einer
anderen Person zuordnen, mehrfach auswählen und über das Kontextmenü zu einer
Gruppe zusammenlegen. Löschen ist möglich.

Weiter einstellbar: Popup-Position (Mauszeiger, Bildschirmmitte, unter der
Menüleiste) und Start beim Anmelden. Autostart ist voreingestellt, sonst sind
die Hotkeys nach jedem Neustart tot.

Das Menüleisten-Icon ist ein monochromes Template-Symbol, zwei Striche mit
einem Riegel dazwischen. Ein Klick öffnet ein Menü mit „Wörterbuch…",
„Einstellungen…" und „Beenden".

## Was die App nicht tut

Kein Verlauf. Der letzte Vorgang liegt im Arbeitsspeicher und ist mit dem
Beenden weg. Keine automatische Tastatureingabe. Keine Netzwerkverbindung.

## Qualitätssicherung

Ein Testkorpus mit erfundenen deutschen Beispieltexten — Bank-Mail,
Aktenvermerk, Beschwerde — läuft automatisch gegen die Erkennung. Ohne das
driftet die Regelbasis unbemerkt. Echte Kundendaten kommen nicht in den Korpus.

## Ausbaustufen

1. Menüleiste, beide Hotkeys, Popup, Regelerkennung, Wörterbuch. Ab hier
   benutzbar.
2. Einstellungsfenster mit Hotkey-Aufnahme und Wörterbuch-Editor.
3. Aliasgruppen, Tippfehler-Toleranz, Verschlüsselung.

## Projektablage

Der Ordner heißt künftig `Textschleuse` statt `Texyschleuse` und bekommt ein
Git-Repo.
