import AppKit
import Carbon.HIToolbox
import TextschleuseCore

/// Prüft die Teile, die kein Unit-Test erreicht: Keychain, Zwischenablage und
/// die Anmeldung eines globalen Kurzbefehls. Läuft ohne Oberfläche und beendet
/// sich selbst.
///
///     Textschleuse.app/Contents/MacOS/Textschleuse --selbsttest
///
/// Sinnvoll nach einem Rechnerwechsel oder wenn ein Kurzbefehl nicht mehr
/// anspringt.
enum Selbsttest {

    static func laufen() -> Never {
        var fehler = 0
        // Zähler statt Zufall, damit „PERSON_1" in den Prüfungen lesbar bleibt.
        Decknamen.zaehleFuerPruefungen()

        print("Textschleuse Selbsttest")
        print("Programm: \(Bundle.main.bundlePath)")
        print("Kennung:  \(Bundle.main.bundleIdentifier ?? "keine")")
        print("")

        fehler += pruefeKeychain()
        fehler += pruefeZwischenablage()
        fehler += pruefeKurzbefehl()
        fehler += pruefeDarstellung()
        fehler += pruefeRueckrechnung()
        fehler += pruefeSuche()
        fehler += pruefeMarkierenImPopup()
        fehler += pruefeWoerterbuchfenster()
        fehler += pruefeHauptfenster()
        fehler += pruefeBearbeiten()
        fehler += pruefeSprungZurFundstelle()
        fehler += pruefeZiffernBeiMarkierung()
        fehler += pruefeInlineDecknamen()
        fehler += pruefeWiderruf()
        fehler += pruefeSitzung()
        fehler += pruefeZuordnenImRueckweg()
        fehler += pruefeKnoepfeUndMenue()
        fehler += pruefePfeiltasten()
        fehler += pruefeWoerterbuchDaneben()
        fehler += pruefeEinstellungen()
        fehler += pruefeWeiterspringen()
        fehler += pruefeFenstergroesse()
        fehler += pruefeZuordnungsliste()
        fehler += pruefeWoerterbuchBeiEnge()
        fehler += pruefeKorrekturImText()
        fehler += pruefeIgnorierenImRueckweg()
        fehler += pruefeFreiliste()
        fehler += pruefeZusatzKategorien()
        fehler += pruefeChipOhnePolster()
        fehler += pruefeNormalesBearbeiten()
        fehler += pruefeTastenkuerzelBlatt()

        print("")
        print(fehler == 0 ? "Alles in Ordnung." : "\(fehler) Punkt(e) fehlgeschlagen.")
        exit(fehler == 0 ? 0 : 1)
    }

    private static func pruefeKeychain() -> Int {
        let ordner = FileManager.default.temporaryDirectory
            .appendingPathComponent("textschleuse-selbsttest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: ordner) }

        let speicher = Speicher(ordner: ordner)
        // Der Selbsttest darf den gelebten Bestand nicht anfassen. Wenn diese
        // Zusicherung je bricht, soll es hier auffallen und nicht dort.
        guard !speicher.istEchterBestand else {
            print("✗ Keychain: der Selbsttest zeigt auf den echten Bestand — abgebrochen")
            return 1
        }
        print("✓ Bestand: der Selbsttest arbeitet in \(ordner.lastPathComponent), "
            + "nicht in \(Speicher.echterOrdner.lastPathComponent)")

        var buch = Woerterbuch()
        _ = buch.anlegen(text: "Selbsttest Person", kategorie: .person)

        do {
            try speicher.sichern(buch)
            let geladen = try Speicher(ordner: ordner).laden()
            guard geladen.eintraege.first?.text == "Selbsttest Person" else {
                print("✗ Keychain: geladen, aber der Inhalt stimmt nicht")
                return 1
            }
            print("✓ Keychain: Schlüssel gelesen, verschlüsselt geschrieben und wieder gelesen")
            return 0
        } catch {
            print("✗ Keychain: \(error.localizedDescription)")
            print("  Ohne Zugriff läuft die App nicht. Ist das Bundle signiert? "
                + "Prüfen mit: codesign --verify --verbose \(Bundle.main.bundlePath)")
            return 1
        }
    }

    private static func pruefeZwischenablage() -> Int {
        let vorher = Zwischenablage.lies()
        defer { if let vorher { Zwischenablage.schreib(vorher) } }

        let probe = "Textschleuse Selbsttest \(UUID().uuidString)"
        Zwischenablage.schreib(probe)
        guard Zwischenablage.lies() == probe else {
            print("✗ Zwischenablage: geschrieben, aber anders zurückgelesen")
            return 1
        }
        print("✓ Zwischenablage: schreiben und lesen")
        return 0
    }

    /// Baut das Popup wirklich auf und misst, was darin steht. Ein leeres
    /// Textfeld sieht man auf dem Bildschirm sofort, aber erst, wenn man
    /// hinschaut — das hier fällt beim Bauen auf.
    private static func pruefeDarstellung() -> Int {
        let probe = """
            Sehr geehrter Herr Nyström, anbei die Unterlagen zur Kontoverbindung \
            DE89 3704 0044 0532 0130 00. Rückfragen an almut.weidenbach@example.org \
            oder 0621 1234567.
            """
        let analyse = Schleuse.analysiere(probe, woerterbuch: Woerterbuch())
        guard !analyse.funde.isEmpty else {
            print("✗ Darstellung: im Probetext nichts gefunden")
            return 1
        }

        var fehler = 0
        let popup = SchutzPopup(analyse: analyse) { _ in }
        popup.layoutIfNeeded()

        guard let inhalt = popup.contentView else {
            print("✗ Darstellung: das Fenster hat keinen Inhalt")
            return 1
        }

        // Kein Textfeld darf leer sein, und die Textfläche muss den größten
        // Teil der Höhe bekommen.
        let flaeche = rollflaecheSuchen(in: inhalt)
        let text = flaeche?.documentView as? NSTextView

        if let text, !text.string.isEmpty {
            print("✓ Darstellung: \(text.string.count) Zeichen im Textfeld, "
                + "\(analyse.funde.count) Fundstellen")
        } else {
            print("✗ Darstellung: das Textfeld ist leer")
            fehler += 1
        }

        if let flaeche {
            let anteil = flaeche.frame.height / inhalt.frame.height
            if anteil > 0.4 {
                print(String(format: "✓ Darstellung: Textfläche belegt %.0f %% der Fensterhöhe", anteil * 100))
            } else {
                print(String(format: "✗ Darstellung: Textfläche belegt nur %.0f %% der Fensterhöhe", anteil * 100))
                fehler += 1
            }
        }

        // Zeigt die Liste rechts die Fundstellen?
        let tabelle = tabelleSuchen(in: inhalt)
        if let tabelle, tabelle.numberOfRows == analyse.funde.count {
            print("✓ Darstellung: \(tabelle.numberOfRows) Zeilen in der Fundstellenliste")
        } else {
            print("✗ Darstellung: die Fundstellenliste zeigt "
                + "\(tabelle?.numberOfRows ?? -1) statt \(analyse.funde.count) Zeilen")
            fehler += 1
        }

        // Stehen Text und Liste nebeneinander, oder ist eins von beiden
        // hinter dem anderen verschwunden?
        if let flaeche, let tabellenRolle = tabelle?.enclosingScrollView {
            let links = inhalt.convert(flaeche.bounds, from: flaeche)
            let rechts = inhalt.convert(tabellenRolle.bounds, from: tabellenRolle)
            let nebeneinander = links.maxX <= rechts.minX + 1
            let beideBreit = links.width > 200 && rechts.width > 120
            if nebeneinander && beideBreit {
                print("✓ Aufbau: Text links (\(Int(links.width)) pt), Liste rechts (\(Int(rechts.width)) pt)")
            } else {
                print("✗ Aufbau: Text \(NSStringFromRect(links)), Liste \(NSStringFromRect(rechts))")
                fehler += 1
            }
        } else {
            print("✗ Aufbau: Textfläche oder Liste nicht gefunden")
            fehler += 1
        }

        // Sitzt der Inhalt tatsächlich im Fenster oder ist er in eine Ecke
        // zusammengefallen?
        let fensterflaeche = popup.frame.width * popup.frame.height
        let inhaltsflaeche = inhalt.frame.width * inhalt.frame.height
        if inhaltsflaeche > fensterflaeche * 0.9 {
            print("✓ Darstellung: der Inhalt füllt das Fenster")
        } else {
            print("✗ Darstellung: der Inhalt füllt das Fenster nicht "
                + "(\(Int(inhalt.frame.width))×\(Int(inhalt.frame.height)) "
                + "in \(Int(popup.frame.width))×\(Int(popup.frame.height)))")
            fehler += 1
        }

        popup.orderOut(nil)
        fehler += pruefeLeerzustand()
        return fehler
    }

    /// Ohne Fundstellen und ohne Text muss das Fenster trotzdem stehen und
    /// etwas sagen. Vorher hat es sich in diesem Fall selbst geschlossen, was
    /// aussah, als sei der Kurzbefehl nicht angekommen.
    private static func pruefeLeerzustand() -> Int {
        var fehler = 0
        for (name, text) in [("nichts erkannt", "Ein völlig harmloser Satz."), ("kein Text", "")] {
            let analyse = Schleuse.analysiere(text, woerterbuch: Woerterbuch())
            guard analyse.funde.isEmpty else {
                print("✗ Leerzustand (\(name)): der Probetext hat doch Fundstellen")
                fehler += 1
                continue
            }

            let popup = SchutzPopup(analyse: analyse) { _ in }
            popup.layoutIfNeeded()
            let inhalt = popup.contentView
            let kopf = beschriftungenSammeln(in: inhalt).filter { !$0.isEmpty }

            if let inhalt, inhalt.frame.width > 400, !kopf.isEmpty {
                print("✓ Leerzustand (\(name)): Fenster steht, Kopfzeile sagt „\(kopf[0])\"")
            } else {
                print("✗ Leerzustand (\(name)): Fenster leer oder zu klein")
                fehler += 1
            }
            popup.orderOut(nil)
        }
        return fehler
    }

    private static func beschriftungenSammeln(in ansicht: NSView?) -> [String] {
        guard let ansicht, !ansicht.isHidden else { return [] }
        var gefunden: [String] = []
        if let feld = ansicht as? NSTextField, !feld.isEditable, !feld.stringValue.isEmpty {
            gefunden.append(feld.stringValue)
        }
        for unter in ansicht.subviews {
            gefunden += beschriftungenSammeln(in: unter)
        }
        return gefunden
    }

    /// Die Darstellung ist nicht der Originaltext: Chips schieben Platzhalter
    /// dazwischen, lange Passagen sind eingeklappt. Eine Markierung mit der
    /// Maus muss trotzdem auf der richtigen Stelle im Original landen.
    private static func pruefeRueckrechnung() -> Int {
        // Lang genug, dass Chiptext einklappt.
        let fuellung = String(repeating: "Sonst nichts Auffälliges in diesem Absatz. ", count: 12)
        let text = "Herr Nyström schrieb an almut@example.org. \(fuellung)Projekt Nordlicht läuft."
        let analyse = Schleuse.analysiere(text, woerterbuch: Woerterbuch())
        let aufbau = Chiptext.aufbauen(analyse: analyse, ausgewaehlt: nil)

        var fehler = 0
        let original = text as NSString

        for gesucht in ["Nordlicht", "Sonst"] {
            let imOriginal = original.range(of: gesucht)
            // Die Stelle in der Darstellung suchen und zurückrechnen.
            let inAnzeige = (aufbau.text.string as NSString).range(of: gesucht)
            guard inAnzeige.location != NSNotFound else {
                print("✗ Rückrechnung: „\(gesucht)\" steht nicht in der Darstellung")
                fehler += 1
                continue
            }
            let zurueck = Chiptext.originalBereich(fuer: inAnzeige, in: aufbau.text)
            if zurueck == imOriginal {
                print("✓ Rückrechnung: „\(gesucht)\" landet auf der richtigen Stelle")
            } else {
                print("✗ Rückrechnung: „\(gesucht)\" → \(zurueck.map(NSStringFromRange) ?? "nichts"), "
                    + "erwartet \(NSStringFromRange(imOriginal))")
                fehler += 1
            }
        }

        // Eine Markierung über einem Chip muss auf den Fund zeigen.
        if let fund = analyse.aktiveFunde.first(where: { $0.kategorie == .email }),
           let chipBereich = aufbau.bereiche[fund.id] {
            let zurueck = Chiptext.originalBereich(fuer: chipBereich, in: aufbau.text)
            if zurueck == fund.bereich {
                print("✓ Rückrechnung: Markierung über einem Chip trifft den Fund")
            } else {
                print("✗ Rückrechnung: Markierung über einem Chip zeigt auf \(zurueck.map(NSStringFromRange) ?? "nichts")")
                fehler += 1
            }
        }
        return fehler
    }

    /// Der Weg, den du im Popup gehst: markieren, Kategorie drücken, Deckname
    /// ändern. Ohne Bildschirm nachgestellt.
    private static func pruefeMarkierenImPopup() -> Int {
        let text = "Das Projekt Nordlicht startet im Frühjahr."
        var analyse = Schleuse.analysiere(text, woerterbuch: Woerterbuch())
        var fehler = 0

        guard let kennung = Schleuse.markiere(
            bereich: (text as NSString).range(of: "Nordlicht"),
            als: .begriff,
            merken: true,
            in: &analyse
        ) else {
            print("✗ Markieren: die Markierung wurde nicht angenommen")
            return 1
        }

        if analyse.woerterbuch.eintrag(fuerText: "Nordlicht") != nil {
            print("✓ Markieren: der Begriff liegt im Wörterbuch")
        } else {
            print("✗ Markieren: der Begriff fehlt im Wörterbuch")
            fehler += 1
        }

        do {
            try Schleuse.benenneUm(fundId: kennung, auf: "projekt_n", in: &analyse)
            let geschuetzt = Schleuse.geschuetzterText(analyse)
            if geschuetzt.contains("PROJEKT_N") {
                print("✓ Markieren: eigener Deckname steht im Ergebnis")
            } else {
                print("✗ Markieren: eigener Deckname fehlt im Ergebnis")
                fehler += 1
            }

            let zurueck = Rueckweg.analysiere(
                geschuetzt,
                woerterbuch: analyse.woerterbuch,
                unbekannte: analyse.unbekannte
            )
            if zurueck.ergebnis == text {
                print("✓ Markieren: der Rückweg stellt den Text wieder her")
            } else {
                print("✗ Markieren: der Rückweg liefert etwas anderes")
                fehler += 1
            }
        } catch {
            print("✗ Markieren: Umbenennen fehlgeschlagen (\(error.localizedDescription))")
            fehler += 1
        }
        return fehler
    }

    /// ⌘F: findet die Suche, was dasteht, und springt sie an?
    private static func pruefeSuche() -> Int {
        let text = """
            Sehr geehrter Herr Nyström, das Projekt Nordlicht läuft.             Zu Nordlicht gehört auch die Abteilung Kredit. Nordlicht endet im Mai.
            """
        let analyse = Schleuse.analysiere(text, woerterbuch: Woerterbuch())
        let popup = SchutzPopup(analyse: analyse) { _ in }
        popup.layoutIfNeeded()
        defer { popup.orderOut(nil) }

        guard let inhalt = popup.contentView,
              let suche = suchzeileSuchen(in: inhalt),
              let textAnsicht = rollflaecheSuchen(in: inhalt)?.documentView as? NSTextView
        else {
            print("✗ Suche: Suchzeile oder Textfläche nicht gefunden")
            return 1
        }

        var fehler = 0
        suche.oeffne()

        let treffer = suche.suche(nach: "nordlicht")
        if treffer == 3 {
            print("✓ Suche: 3 Treffer, Groß- und Kleinschreibung egal")
        } else {
            print("✗ Suche: \(treffer) Treffer statt 3")
            fehler += 1
        }

        // Der erste Treffer muss angesprungen und markiert sein.
        let markiert = (textAnsicht.string as NSString).substring(with: textAnsicht.selectedRange())
        if markiert.lowercased() == "nordlicht" {
            print("✓ Suche: der erste Treffer ist markiert")
        } else {
            print("✗ Suche: markiert ist „\(markiert)\" statt „Nordlicht\"")
            fehler += 1
        }

        // Weiterspringen muss eine andere Stelle treffen.
        let ersteStelle = textAnsicht.selectedRange().location
        suche.naechster()
        if textAnsicht.selectedRange().location != ersteStelle {
            print("✓ Suche: ⌘G springt zum nächsten Treffer")
        } else {
            print("✗ Suche: ⌘G bleibt stehen")
            fehler += 1
        }

        if suche.suche(nach: "gibtesnicht") == 0 {
            print("✓ Suche: was nicht dasteht, wird nicht gefunden")
        } else {
            print("✗ Suche: Treffer für einen Begriff, der nicht im Text steht")
            fehler += 1
        }

        suche.schliesse()
        if !suche.istOffen {
            print("✓ Suche: ⎋ klappt die Zeile wieder zu")
        } else {
            print("✗ Suche: die Zeile bleibt offen")
            fehler += 1
        }
        return fehler
    }

    /// Baut das Wörterbuchfenster auf und bedient den Editor über dieselben
    /// Befehle, die die Knöpfe schicken.
    private static func pruefeWoerterbuchfenster() -> Int {
        var buch = Woerterbuch()
        let person = buch.anlegen(text: "Thorben Nystrom", kategorie: .person)
        _ = buch.aliasHinzufuegen("Nystrom", zu: person.id)
        _ = buch.anlegen(text: "beispiel@example.org", kategorie: .email, automatischErkannt: true)

        var gesichert: Woerterbuch?
        let inhalt = WoerterbuchAnsicht(
            woerterbuch: buch,
            beimSichern: { gesichert = $0 },
            beimExportieren: { _, _ in }
        )
        let fenster = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 560),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        fenster.contentView = inhalt
        fenster.layoutIfNeeded()
        defer { fenster.orderOut(nil) }

        var fehler = 0

        // Liste: zwei Einträge, einer davon mit Schreibweise, macht drei Zeilen.
        // Es gibt zwei Tabellen — „Im Text" und „Alle". Gemeint ist die volle.
        let tabelle = tabellenSammeln(in: inhalt).max { $0.numberOfRows < $1.numberOfRows }
        if let tabelle, datenzeilen(tabelle) == 3 {
            print("✓ Wörterbuch: 3 Zeilen, Schreibweise eingerückt unter der Hauptnennung")
        } else {
            print("✗ Wörterbuch: \(tabelle.map(datenzeilen) ?? -1) Zeilen statt 3")
            fehler += 1
        }

        guard let editor = editorSuchen(in: inhalt) else {
            print("✗ Wörterbuch: der Editor fehlt")
            return fehler + 1
        }

        // Ohne Auswahl darf nichts passieren.
        if editor.beiBefehl?(.begriff("Egal")) == nil, gesichert == nil {
            print("✓ Wörterbuch: ohne Auswahl ändert der Editor nichts")
        } else {
            print("✗ Wörterbuch: der Editor hat ohne Auswahl etwas geändert")
            fehler += 1
        }

        // Jetzt den Eintrag auswählen und den Tippfehler beheben.
        inhalt.waehle(person.id)
        if let meldung = editor.beiBefehl?(.begriff("Thorben Nyström")) {
            print("✗ Wörterbuch: Begriff ändern meldet „\(meldung)\"")
            fehler += 1
        } else if gesichert?.eintrag(mitId: person.id)?.text == "Thorben Nyström" {
            print("✓ Wörterbuch: Begriff geändert und gesichert")
        } else {
            print("✗ Wörterbuch: der Begriff wurde nicht übernommen")
            fehler += 1
        }

        // Deckname vergeben.
        if editor.beiBefehl?(.deckname("mandant_a")) == nil,
           gesichert?.eintrag(mitId: person.id)?.platzhalter == "MANDANT_A" {
            print("✓ Wörterbuch: Deckname vergeben")
        } else {
            print("✗ Wörterbuch: der Deckname wurde nicht übernommen")
            fehler += 1
        }

        // Ein ungültiger Name muss abgelehnt werden, ohne etwas zu ändern.
        let meldung = editor.beiBefehl?(.deckname("MIT LEERZEICHEN"))
        if meldung != nil, gesichert?.eintrag(mitId: person.id)?.platzhalter == "MANDANT_A" {
            print("✓ Wörterbuch: ungültiger Deckname abgelehnt, alter bleibt")
        } else {
            print("✗ Wörterbuch: ungültiger Deckname ging durch")
            fehler += 1
        }

        // Kategorie wechseln, eigener Deckname muss bleiben.
        if editor.beiBefehl?(.kategorie(.firma)) == nil,
           gesichert?.eintrag(mitId: person.id)?.kategorie == .firma,
           gesichert?.eintrag(mitId: person.id)?.platzhalter == "MANDANT_A" {
            print("✓ Wörterbuch: Typ gewechselt, eigener Deckname bleibt")
        } else {
            print("✗ Wörterbuch: der Typwechsel ging schief")
            fehler += 1
        }

        // Schreibweise anlegen und wieder löschen.
        if editor.beiBefehl?(.aliasNeu("Nyström")) == nil,
           let alias = gesichert?.eintrag(mitId: person.id)?.aliase.last {
            let vorher = gesichert?.eintrag(mitId: person.id)?.aliase.count ?? 0
            _ = editor.beiBefehl?(.aliasLoeschen(alias.id))
            let nachher = gesichert?.eintrag(mitId: person.id)?.aliase.count ?? 0
            if nachher == vorher - 1 {
                print("✓ Wörterbuch: Schreibweise angelegt und gelöscht")
            } else {
                print("✗ Wörterbuch: die Schreibweise ließ sich nicht löschen")
                fehler += 1
            }
        } else {
            print("✗ Wörterbuch: die Schreibweise ließ sich nicht anlegen")
            fehler += 1
        }

        // Nachschlagen: tippt man einen Decknamen ins Suchfeld, muss die
        // Antwort dastehen.
        if let feld = suchfeldSuchen(in: inhalt) {
            feld.stringValue = "PERSON_1"
            inhalt.filterGeaendert()
            let saetze = beschriftungenSammeln(in: inhalt)
            if saetze.contains(where: { $0.contains("PERSON_1 ist Thorben Nyström") }) {
                print("✓ Wörterbuch: Deckname nachschlagen zeigt den Klartext")
            } else {
                print("✗ Wörterbuch: die Auflösungszeile fehlt")
                fehler += 1
            }

            feld.stringValue = "GIBTESNICHT"
            inhalt.filterGeaendert()
            let danach = beschriftungenSammeln(in: inhalt)
            if !danach.contains(where: { $0.contains(" ist ") && $0.contains("Nyström") }) {
                print("✓ Wörterbuch: ohne Treffer bleibt die Zeile weg")
            } else {
                print("✗ Wörterbuch: die Auflösungszeile steht ohne Treffer da")
                fehler += 1
            }
            feld.stringValue = ""
            inhalt.filterGeaendert()
        } else {
            print("✗ Wörterbuch: das Suchfeld fehlt")
            fehler += 1
        }

        // Alte Decknamen müssen weiter auflösen.
        if gesichert?.klartext(fuerPlatzhalter: "PERSON_1") == "Thorben Nyström" {
            print("✓ Wörterbuch: der ursprüngliche Deckname löst weiter auf")
        } else {
            print("✗ Wörterbuch: PERSON_1 löst nicht mehr auf")
            fehler += 1
        }
        return fehler
    }

    /// Das Hauptfenster: ein Textfeld, zwei Richtungen. Beim Umschalten
    /// bleibt der Text stehen, die Verläufe bleiben getrennt.
    private static func pruefeHauptfenster() -> Int {
        var fehler = 0
        var gesichert: Analyse?
        let sitzung = Sitzung()

        let fenster = Hauptfenster(
            woerterbuch: { Woerterbuch() },
            sitzung: sitzung,
            beimSchuetzen: { analyse, _ in gesichert = analyse },
            beimZurueckdrehen: { _ in }
        )
        fenster.window?.layoutIfNeeded()
        defer { fenster.close() }

        guard let inhalt = fenster.window?.contentView else {
            print("✗ Hauptfenster: kein Inhalt")
            return 1
        }

        if segmentSuchen(in: inhalt)?.segmentCount == 2 {
            print("✓ Hauptfenster: ein Umschalter mit Schützen und Zurückdrehen")
        } else {
            print("✗ Hauptfenster: kein Umschalter mit zwei Richtungen")
            fehler += 1
        }

        // Die Arbeitsfläche steht von Anfang an da, leer, zum Einfügen.
        guard let flaeche = schutzflaecheSuchen(in: inhalt) else {
            print("✗ Hauptfenster: keine Arbeitsfläche zum Schützen")
            return fehler + 1
        }
        if flaeche.analyse.original.isEmpty {
            print("✓ Hauptfenster: startet mit leerem Textfeld")
        } else {
            print("✗ Hauptfenster: startet mit „\(flaeche.analyse.original)\"")
            fehler += 1
        }

        let text = "Herr Nyström schrieb an almut@example.org."
        flaeche.setzeTextFuerPruefung(text)
        fenster.window?.layoutIfNeeded()
        if flaeche.analyse.funde.count >= 2 {
            print("✓ Hauptfenster: aus getipptem Text werden \(flaeche.analyse.funde.count) Fundstellen")
        } else {
            print("✗ Hauptfenster: getippter Text bringt \(flaeche.analyse.funde.count) Fundstellen")
            fehler += 1
        }
        if sitzung.vorgaenge.count == 1 {
            print("✓ Hauptfenster: der getippte Text steht im Verlauf")
        } else {
            print("✗ Hauptfenster: \(sitzung.vorgaenge.count) Vorgänge statt 1")
            fehler += 1
        }

        // Umschalten: derselbe Text, jetzt im Rückweg.
        fenster.wechsle(zu: .zurueckdrehen)
        fenster.window?.layoutIfNeeded()
        guard let rueckweg = rueckwegflaecheSuchen(in: inhalt) else {
            print("✗ Hauptfenster: nach dem Umschalten keine Rückweg-Fläche")
            return fehler + 1
        }
        if rueckweg.ergebnis.original == text {
            print("✓ Hauptfenster: beim Umschalten bleibt der Text stehen")
        } else {
            print("✗ Hauptfenster: im Rückweg steht „\(rueckweg.ergebnis.original)\"")
            fehler += 1
        }
        if schutzflaecheSuchen(in: inhalt) == nil {
            print("✓ Hauptfenster: nur eine Fläche zur Zeit")
        } else {
            print("✗ Hauptfenster: beide Flächen zugleich im Fenster")
            fehler += 1
        }
        if sitzung.rueckwegVorgaenge.count == 1, sitzung.vorgaenge.count == 1 {
            print("✓ Hauptfenster: zwei getrennte Verläufe, je ein Eintrag")
        } else {
            print("✗ Hauptfenster: Verläufe \(sitzung.vorgaenge.count) / \(sitzung.rueckwegVorgaenge.count)")
            fehler += 1
        }

        // Und zurück: derselbe Text, kein neuer Vorgang.
        fenster.wechsle(zu: .schuetzen)
        fenster.window?.layoutIfNeeded()
        if flaeche.analyse.original == text, sitzung.vorgaenge.count == 1 {
            print("✓ Hauptfenster: zurück zum Schützen mit demselben Text, ohne neuen Vorgang")
        } else {
            print("✗ Hauptfenster: zurück steht „\(flaeche.analyse.original)\", \(sitzung.vorgaenge.count) Vorgänge")
            fehler += 1
        }

        // Übernehmen muss nach oben gemeldet werden.
        flaeche.uebernehmen(merken: false)
        if gesichert != nil {
            print("✓ Hauptfenster: Übernehmen meldet das Ergebnis nach oben")
        } else {
            print("✗ Hauptfenster: Übernehmen kam nicht an")
            fehler += 1
        }
        return fehler
    }

    /// Der Text lässt sich bearbeiten wie jeder andere: alles markieren und
    /// löschen, hinter einem Chip ⌫ drücken. Nur mitten in einen Decknamen
    /// tippen geht nicht.
    private static func pruefeNormalesBearbeiten() -> Int {
        var fehler = 0
        let text = "Sehr geehrter Herr Nyström, Rückfragen an a@b.de."
        let analyse = Schleuse.analysiere(text, woerterbuch: Woerterbuch())
        let aufbau = Chiptext.aufbauen(analyse: analyse, ausgewaehlt: nil)
        let alles = NSRange(location: 0, length: aufbau.text.length)

        func regel(_ bereich: NSRange, _ ersatz: String) -> Chiptext.Aenderung {
            Chiptext.pruefeAenderung(bereich: bereich, ersatz: ersatz, in: aufbau.text, chips: aufbau.bereiche)
        }

        if regel(alles, "") == .erlaubt {
            print("✓ Bearbeiten: alles markieren und ⌫ ist erlaubt")
        } else {
            print("✗ Bearbeiten: alles markieren und ⌫ wird verweigert")
            fehler += 1
        }

        guard let fund = analyse.funde.first(where: { $0.text.contains("Nyström") }),
              let chip = aufbau.bereiche[fund.id]
        else {
            print("✗ Bearbeiten: Nyström nicht gefunden")
            return fehler + 1
        }
        let letzter = NSRange(location: NSMaxRange(chip) - 1, length: 1)
        if case .ausweiten(let ganz) = regel(letzter, ""), ganz == chip {
            print("✓ Bearbeiten: ⌫ hinter dem Chip nimmt den ganzen Chip")
        } else {
            print("✗ Bearbeiten: ⌫ hinter dem Chip: \(regel(letzter, ""))")
            fehler += 1
        }
        if regel(NSRange(location: NSMaxRange(chip) - 2, length: 0), "x") == .verboten {
            print("✓ Bearbeiten: mitten im Decknamen tippen bleibt verboten")
        } else {
            print("✗ Bearbeiten: mitten im Decknamen darf man tippen")
            fehler += 1
        }
        if regel(NSRange(location: chip.location, length: 0), "x") == .erlaubt {
            print("✓ Bearbeiten: vor dem Chip tippen ist erlaubt")
        } else {
            print("✗ Bearbeiten: vor dem Chip tippen wird verweigert")
            fehler += 1
        }

        // In der echten Ansicht: leeren durch Löschen.
        let ansicht = SchutzAnsicht(analyse: analyse)
        let fenster = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        fenster.contentView = ansicht
        fenster.layoutIfNeeded()
        defer { fenster.orderOut(nil) }
        if ansicht.darfAendernFuerPruefung(alles) {
            print("✓ Bearbeiten: die Ansicht lässt Alles-löschen zu")
        } else {
            print("✗ Bearbeiten: die Ansicht sperrt Alles-löschen")
            fehler += 1
        }
        ansicht.setzeTextFuerPruefung("")
        if ansicht.analyse.original.isEmpty, ansicht.analyse.funde.isEmpty {
            print("✓ Bearbeiten: danach ist der Text leer")
        } else {
            print("✗ Bearbeiten: nach dem Löschen steht noch „\(ansicht.analyse.original)\"")
            fehler += 1
        }

        // Der Rückweg ist genauso bearbeitbar.
        var buch = Woerterbuch()
        _ = buch.anlegen(text: "Thorben Nyström", kategorie: .person)
        let rueckweg = RueckwegAnsicht(ergebnis: Rueckweg.analysiere("", woerterbuch: buch), woerterbuch: buch)
        fenster.contentView = rueckweg
        fenster.layoutIfNeeded()
        rueckweg.setzeTextFuerPruefung("Grüße an PERSON_1 und PERSON_9.")
        if rueckweg.ergebnis.original == "Grüße an PERSON_1 und PERSON_9.", rueckweg.ergebnis.funde.count == 2 {
            print("✓ Bearbeiten: getippter Text im Rückweg wird aufgelöst")
        } else {
            print("✗ Bearbeiten: im Rückweg steht „\(rueckweg.ergebnis.original)\" mit \(rueckweg.ergebnis.funde.count) Platzhaltern")
            fehler += 1
        }
        let rueckwegAlles = NSRange(location: 0, length: (rueckweg.ergebnis.original as NSString).length + 20)
        _ = rueckwegAlles
        if rueckweg.darfAendernFuerPruefung(NSRange(location: 0, length: 3)) {
            print("✓ Bearbeiten: im Rückweg lässt sich der Text ändern")
        } else {
            print("✗ Bearbeiten: der Rückweg-Text ist gesperrt")
            fehler += 1
        }
        return fehler
    }

    /// Die Tastenkürzel-Übersicht: baut sich auf, nennt die eingestellten
    /// Kurzbefehle, und jede Arbeitsfläche hat den Knopf dafür.
    private static func pruefeTastenkuerzelBlatt() -> Int {
        var fehler = 0
        let inhalt = Tastenkuerzel.baueInhalt()
        let texte = beschriftungenSammeln(in: inhalt)
        let schuetzen = Einstellungen.gemeinsam.kurzbefehlSchuetzen.beschriftung
        if texte.contains(schuetzen) {
            print("✓ Tastenkürzel: das Blatt nennt den eingestellten Kurzbefehl \(schuetzen)")
        } else {
            print("✗ Tastenkürzel: der Kurzbefehl \(schuetzen) fehlt im Blatt")
            fehler += 1
        }
        let knoepfe = knoepfeSammeln(in: inhalt).map(\.title)
        if texte.contains("⌘⏎"), knoepfe.contains("Beim Start zeigen") {
            print("✓ Tastenkürzel: Kopieren und das Start-Häkchen stehen drin")
        } else {
            print("✗ Tastenkürzel: Kopieren oder Start-Häkchen fehlen (\(knoepfe))")
            fehler += 1
        }

        let schutz = SchutzAnsicht(analyse: Schleuse.analysiere("x", woerterbuch: Woerterbuch()))
        let rueckweg = RueckwegAnsicht(ergebnis: Rueckweg.analysiere("x", woerterbuch: Woerterbuch()))
        for (name, ansicht) in [("Schützen", schutz as NSView), ("Zurückdrehen", rueckweg)] {
            if knoepfeSammeln(in: ansicht).contains(where: { $0.title == "Tastenkürzel" }) {
                print("✓ Tastenkürzel: Knopf in der Fläche \(name)")
            } else {
                print("✗ Tastenkürzel: kein Knopf in der Fläche \(name)")
                fehler += 1
            }
        }
        return fehler
    }

    /// Bearbeiten und Leeren: kommt man an den Originaltext heran, und wird
    /// danach richtig neu geprüft?
    private static func pruefeBearbeiten() -> Int {
        var fehler = 0
        let ansicht = SchutzAnsicht(
            analyse: Schleuse.analysiere("Herr Nyström rief an.", woerterbuch: Woerterbuch())
        )
        let fenster = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        fenster.contentView = ansicht
        fenster.layoutIfNeeded()
        defer { fenster.orderOut(nil) }

        let vorher = ansicht.analyse.funde.count

        // Direkt im Text tippen.
        ansicht.setzeTextFuerPruefung("Frau Weidenbach rief an, Nummer 0621 1234567.")

        if ansicht.analyse.original.contains("Weidenbach") {
            print("✓ Bearbeiten: der geänderte Text ist übernommen")
        } else {
            print("✗ Bearbeiten: der Text wurde nicht übernommen")
            fehler += 1
        }
        if ansicht.analyse.funde.contains(where: { $0.kategorie == .telefon }) {
            print("✓ Bearbeiten: nach dem Ändern wird neu geprüft (\(vorher) → "
                + "\(ansicht.analyse.funde.count) Fundstellen)")
        } else {
            print("✗ Bearbeiten: es wurde nicht neu geprüft")
            fehler += 1
        }

        // Vorschau und zurück.
        ansicht.vorschauUmschaltenFuerPruefung()
        let inVorschau = ansicht.istInVorschauFuerPruefung()
        ansicht.vorschauUmschaltenFuerPruefung()
        if inVorschau, !ansicht.istInVorschauFuerPruefung() {
            print("✓ Vorschau: lässt sich ein- und ausschalten")
        } else {
            print("✗ Vorschau: das Umschalten klemmt")
            fehler += 1
        }

        // Leeren.
        ansicht.leerenFuerPruefung()
        if ansicht.analyse.original.isEmpty, ansicht.analyse.funde.isEmpty {
            print("✓ Leeren: Text und Fundstellen sind weg")
        } else {
            print("✗ Leeren: es steht noch etwas da")
            fehler += 1
        }

        // Und das Wörterbuch überlebt beides.
        var buch = Woerterbuch()
        _ = buch.anlegen(text: "Thorben Nyström", kategorie: .person)
        let zweite = SchutzAnsicht(analyse: Schleuse.analysiere("Thorben Nyström.", woerterbuch: buch))
        zweite.leerenFuerPruefung()
        if zweite.analyse.woerterbuch.eintraege.count == 1 {
            print("✓ Leeren: das Wörterbuch bleibt")
        } else {
            print("✗ Leeren: das Wörterbuch wurde mit weggeworfen")
            fehler += 1
        }
        return fehler
    }

    /// Klick auf eine Fundstelle in der Liste muss den Text dorthin rollen.
    private static func pruefeSprungZurFundstelle() -> Int {
        // Lang genug, dass die letzte Fundstelle außerhalb des Sichtbaren liegt.
        let fuellung = String(repeating: "Ein Absatz ohne alles Auffällige. ", count: 400)
        let text = "Herr Nyström schrieb. \(fuellung) Zuletzt meldete sich Almut Weidenbach."
        let analyse = Schleuse.analysiere(text, woerterbuch: Woerterbuch())

        let ansicht = SchutzAnsicht(analyse: analyse)
        let fenster = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        fenster.contentView = ansicht
        fenster.layoutIfNeeded()
        defer { fenster.orderOut(nil) }

        guard let textAnsicht = rollflaecheSuchen(in: ansicht)?.documentView as? NSTextView,
              let rolle = rollflaecheSuchen(in: ansicht),
              let letzte = analyse.aktiveFunde.last
        else {
            print("✗ Sprung: Textfläche oder Fundstelle fehlt")
            return 1
        }

        // Erst die letzte Fundstelle: sie liegt weit unten und muss nach dem
        // Anklicken im Ausschnitt stehen.
        ansicht.waehleFundFuerPruefung(letzte.id)
        fenster.layoutIfNeeded()
        let letzteSichtbar = ansicht.fundIstSichtbarFuerPruefung(letzte.id)

        // Dann wieder nach oben: der Sprung muss in beide Richtungen gehen.
        guard let erste = analyse.aktiveFunde.first else { return 1 }
        ansicht.waehleFundFuerPruefung(erste.id)
        fenster.layoutIfNeeded()
        let ersteSichtbar = ansicht.fundIstSichtbarFuerPruefung(erste.id)

        var fehler = 0
        if letzteSichtbar {
            print("✓ Sprung: die letzte Fundstelle steht nach dem Anklicken im Ausschnitt")
        } else {
            print("✗ Sprung: die letzte Fundstelle bleibt außerhalb des Ausschnitts")
            fehler += 1
        }
        if ersteSichtbar {
            print("✓ Sprung: zurück nach oben geht genauso")
        } else {
            print("✗ Sprung: der Weg zurück nach oben fehlt")
            fehler += 1
        }
        _ = (rolle, textAnsicht)
        return fehler
    }

    /// Ziffern müssen zweierlei können: tippen und kategorisieren. Der
    /// Unterschied ist, ob etwas markiert ist.
    private static func pruefeZiffernBeiMarkierung() -> Int {
        var fehler = 0
        let text = "Das Projekt Nordlicht startet bald."
        let ansicht = SchutzAnsicht(analyse: Schleuse.analysiere(text, woerterbuch: Woerterbuch()))
        let fenster = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        fenster.contentView = ansicht
        fenster.makeKeyAndOrderFront(nil)
        fenster.layoutIfNeeded()
        defer { fenster.orderOut(nil) }

        // Schreibmarke im Text, nichts markiert: dann tippt die 1 eine Eins.
        ansicht.fokussiereTextFuerPruefung()
        ansicht.markiereFuerPruefung(NSRange(location: 0, length: 0))
        if ansicht.tasteFuerPruefung("1") == false {
            print("✓ Ziffern: Schreibmarke im Text, ohne Markierung tippt die 1 eine Eins")
        } else {
            print("✗ Ziffern: im Text wird die 1 abgefangen")
            fehler += 1
        }

        // Mit Markierung schon.
        ansicht.markiereFuerPruefung((text as NSString).range(of: "Nordlicht"))
        let abgefangen = ansicht.tasteFuerPruefung("1")
        let angelegt = ansicht.analyse.woerterbuch.eintrag(fuerText: "Nordlicht")

        if abgefangen, angelegt?.kategorie == .person {
            print("✓ Ziffern: mit Markierung legt die 1 eine Person im Wörterbuch an")
        } else {
            print("✗ Ziffern: mit Markierung passiert nichts "
                + "(abgefangen: \(abgefangen), Eintrag: \(angelegt?.kategorie.anzeigename ?? "keiner"))")
            fehler += 1
        }
        return fehler
    }

    /// Die Chips stehen im Text, der Text bleibt trotzdem bearbeitbar. Das
    /// steht und fällt damit, dass sich der Originaltext exakt aus der
    /// Anzeige zurückgewinnen lässt.
    private static func pruefeInlineDecknamen() -> Int {
        var fehler = 0
        let text = "Sehr geehrter Herr Nyström, Rückfragen an a@b.de oder 0621 1234567."
        var analyse = Schleuse.analysiere(text, woerterbuch: Woerterbuch())

        let anzeige = Chiptext.aufbauen(analyse: analyse, ausgewaehlt: nil).text
        let zurueck = Chiptext.originaltext(aus: anzeige)
        if zurueck == text {
            print("✓ Inline: der Originaltext lässt sich aus der Anzeige zurückgewinnen")
        } else {
            print("✗ Inline: zurückgewonnen kam „\(zurueck)\" statt „\(text)\"")
            fehler += 1
        }

        // Die Anzeige ist länger als das Original — sonst stünde nichts drin.
        if anzeige.length > (text as NSString).length {
            print("✓ Inline: die Decknamen stehen wirklich im Text "
                + "(\(anzeige.length) statt \(( text as NSString).length) Zeichen)")
        } else {
            print("✗ Inline: in der Anzeige steht kein Deckname")
            fehler += 1
        }

        // Die Schreibmarke muss durch beide Richtungen unverändert kommen.
        var markenStimmen = true
        for stelle in [0, 5, 20, (text as NSString).length] {
            let inAnzeige = Chiptext.anzeigePosition(fuer: stelle, in: anzeige)
            if Chiptext.originalPosition(fuer: inAnzeige, in: anzeige) != stelle { markenStimmen = false }
        }
        if markenStimmen {
            print("✓ Inline: die Schreibmarke übersteht das Hin und Her")
        } else {
            print("✗ Inline: die Schreibmarke verrutscht beim Umrechnen")
            fehler += 1
        }

        // Und jetzt in der echten Ansicht: Decknamen gesperrt, Text frei.
        let ansicht = SchutzAnsicht(analyse: analyse)
        let fenster = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        fenster.contentView = ansicht
        fenster.layoutIfNeeded()
        defer { fenster.orderOut(nil) }

        // Eine Stelle mitten im Deckname suchen.
        let aufbau = Chiptext.aufbauen(analyse: analyse, ausgewaehlt: nil).text
        var imDeckname: Int?
        aufbau.enumerateAttribute(
            Chiptext.istPlatzhalter,
            in: NSRange(location: 0, length: aufbau.length)
        ) { wert, bereich, weiter in
            if wert != nil, bereich.length > 3 {
                imDeckname = bereich.location + 2
                weiter.pointee = true
            }
        }

        if let imDeckname, !ansicht.darfAendernFuerPruefung(NSRange(location: imDeckname, length: 1)) {
            print("✓ Inline: im Deckname lässt sich nichts ändern")
        } else {
            print("✗ Inline: der Deckname ist bearbeitbar")
            fehler += 1
        }
        if ansicht.darfAendernFuerPruefung(NSRange(location: 2, length: 1)) {
            print("✓ Inline: im Originaltext lässt sich ändern")
        } else {
            print("✗ Inline: der Originaltext ist gesperrt")
            fehler += 1
        }

        // Tippen und zurückrechnen im Zusammenspiel.
        _ = analyse
        ansicht.setzeTextFuerPruefung("Frau Weidenbach, Tel. 0621 1234567.")
        if ansicht.analyse.original == "Frau Weidenbach, Tel. 0621 1234567." {
            print("✓ Inline: getippter Text kommt sauber im Original an")
        } else {
            print("✗ Inline: im Original steht „\(ansicht.analyse.original)\"")
            fehler += 1
        }
        return fehler
    }

    /// ⌘Z und ⇧⌘Z: nimmt der Widerruf ganze Stände zurück und wieder vor?
    private static func pruefeWiderruf() -> Int {
        var fehler = 0
        let text = "Das Projekt Nordlicht startet bald."
        let ansicht = SchutzAnsicht(analyse: Schleuse.analysiere(text, woerterbuch: Woerterbuch()))
        let fenster = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        fenster.contentView = ansicht
        fenster.layoutIfNeeded()
        defer { fenster.orderOut(nil) }

        if !ansicht.kannWiderrufenFuerPruefung() {
            print("✓ Widerruf: am Anfang gibt es nichts zurückzunehmen")
        } else {
            print("✗ Widerruf: der Stapel ist schon vor der ersten Änderung voll")
            fehler += 1
        }

        // Eine Kategorie zuweisen …
        ansicht.markiereFuerPruefung((text as NSString).range(of: "Nordlicht"))
        _ = ansicht.tasteFuerPruefung("1")
        let nachZuweisung = ansicht.analyse.woerterbuch.eintraege.count

        // … und zurücknehmen.
        ansicht.widerrufeFuerPruefung()
        let nachWiderruf = ansicht.analyse.woerterbuch.eintraege.count
        if nachZuweisung == 1, nachWiderruf == 0 {
            print("✓ Widerruf: ⌘Z nimmt die Zuweisung samt Wörterbucheintrag zurück")
        } else {
            print("✗ Widerruf: \(nachZuweisung) Einträge vorher, \(nachWiderruf) nachher")
            fehler += 1
        }

        // Und wieder vor.
        ansicht.wiederholeFuerPruefung()
        if ansicht.analyse.woerterbuch.eintraege.count == 1 {
            print("✓ Widerruf: ⇧⌘Z stellt sie wieder her")
        } else {
            print("✗ Widerruf: das Wiederholen bringt nichts zurück")
            fehler += 1
        }

        // Auch getippter Text muss zurückgehen.
        let vorherText = ansicht.analyse.original
        ansicht.setzeTextFuerPruefung("Ganz anderer Text ohne alles.")
        ansicht.widerrufeFuerPruefung()
        if ansicht.analyse.original == vorherText {
            print("✓ Widerruf: auch getippter Text geht zurück")
        } else {
            print("✗ Widerruf: nach dem Zurücknehmen steht „\(ansicht.analyse.original)\"")
            fehler += 1
        }
        return fehler
    }

    /// Der Sitzungsverlauf: mehrere Texte, nichts auf der Platte, und das
    /// Hauptfenster sieht, was im Popup passiert ist.
    private static func pruefeSitzung() -> Int {
        var fehler = 0
        let sitzung = Sitzung()

        let ersterText = "Herr Nyström rief an."
        let zweiterText = "Frau Weidenbach schrieb, Tel. 0621 1234567."
        let ersteKennung = sitzung.beginne(Schleuse.analysiere(ersterText, woerterbuch: Woerterbuch()))
        sitzung.beginne(Schleuse.analysiere(zweiterText, woerterbuch: Woerterbuch()))

        if sitzung.vorgaenge.count == 2, sitzung.neuester?.analyse.original == zweiterText {
            print("✓ Sitzung: zwei Texte behalten, der neueste steht vorn")
        } else {
            print("✗ Sitzung: \(sitzung.vorgaenge.count) Texte, vorn steht "
                + "„\(sitzung.neuester?.analyse.original ?? "nichts")\"")
            fehler += 1
        }

        // Ein älterer Vorgang, der fortgeschrieben wird, rutscht nach vorn.
        var ersteAnalyse = Schleuse.analysiere(ersterText, woerterbuch: Woerterbuch())
        Schleuse.markiere(
            bereich: (ersterText as NSString).range(of: "Nyström"),
            als: .person,
            merken: false,
            in: &ersteAnalyse
        )
        sitzung.aktualisiere(ersteKennung, mit: ersteAnalyse)
        if sitzung.neuester?.id == ersteKennung {
            print("✓ Sitzung: der fortgeschriebene Text rutscht nach vorn")
        } else {
            print("✗ Sitzung: die Reihenfolge stimmt nicht")
            fehler += 1
        }

        // Sitzungsplatzhalter sammeln sich, statt sich zu ersetzen.
        if !sitzung.unbekannte.isEmpty,
           sitzung.unbekannte.values.contains("Nyström") {
            print("✓ Sitzung: die Sitzungsplatzhalter bleiben erhalten")
        } else {
            print("✗ Sitzung: die Sitzungsplatzhalter fehlen")
            fehler += 1
        }

        // Die Obergrenze greift.
        for nummer in 0..<Sitzung.hoechstzahl + 5 {
            sitzung.beginne(Schleuse.analysiere("Text \(nummer)", woerterbuch: Woerterbuch()))
        }
        if sitzung.vorgaenge.count == Sitzung.hoechstzahl {
            print("✓ Sitzung: höchstens \(Sitzung.hoechstzahl) Texte, ältere fallen raus")
        } else {
            print("✗ Sitzung: \(sitzung.vorgaenge.count) Texte trotz Obergrenze")
            fehler += 1
        }

        // Und das Fenster zeigt den neuesten, nicht irgendeinen.
        let fenster = Hauptfenster(
            woerterbuch: { Woerterbuch() },
            sitzung: sitzung,
            beimSchuetzen: { _, _ in },
            beimZurueckdrehen: { _ in }
        )
        fenster.window?.layoutIfNeeded()
        defer { fenster.close() }

        let gezeigt = fenster.window?.contentView.flatMap { schutzflaecheSuchen(in: $0) }
        if gezeigt?.analyse.original == sitzung.neuester?.analyse.original {
            print("✓ Sitzung: das Hauptfenster öffnet mit dem neuesten Text")
        } else {
            print("✗ Sitzung: das Hauptfenster zeigt „\(gezeigt?.analyse.original ?? "nichts")\"")
            fehler += 1
        }
        return fehler
    }

    /// Ein Platzhalter, den das Wörterbuch nicht kennt, muss sich im Rückweg
    /// zuordnen lassen — sonst bleibt der Text für immer halb aufgelöst.
    private static func pruefeZuordnenImRueckweg() -> Int {
        var fehler = 0
        var buch = Woerterbuch()
        let eintrag = buch.anlegen(text: "Thorben Nyström", kategorie: .person)

        let antwort = "Bitte melde dich bei UNBEKANNT_3 wegen des Termins."
        let ergebnis = Rueckweg.analysiere(antwort, woerterbuch: buch)

        var gesichert: Woerterbuch?
        let ansicht = RueckwegAnsicht(ergebnis: ergebnis, woerterbuch: buch)
        ansicht.beiWoerterbuchAenderung = { gesichert = $0 }

        let fenster = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        fenster.contentView = ansicht
        fenster.layoutIfNeeded()
        defer { fenster.orderOut(nil) }

        if ansicht.offeneFuerPruefung() == 1 {
            print("✓ Zuordnen: der unbekannte Platzhalter wird als offen gemeldet")
        } else {
            print("✗ Zuordnen: \(ansicht.offeneFuerPruefung()) offene statt einer")
            fehler += 1
        }

        ansicht.waehleFundFuerPruefung(0)
        if ansicht.zuordnenFuerPruefung(zu: eintrag.id) {
            print("✓ Zuordnen: die Zuordnung wird angenommen")
        } else {
            print("✗ Zuordnen: die Zuordnung schlug fehl")
            fehler += 1
        }

        if ansicht.offeneFuerPruefung() == 0, ansicht.ergebnis.ergebnis.contains("Thorben Nyström") {
            print("✓ Zuordnen: der Text löst danach vollständig auf")
        } else {
            print("✗ Zuordnen: es bleibt etwas offen")
            fehler += 1
        }

        // Und die Änderung muss nach oben gemeldet worden sein, sonst wäre sie
        // beim nächsten Text wieder weg.
        if gesichert?.klartext(fuerPlatzhalter: "UNBEKANNT_3") == "Thorben Nyström" {
            print("✓ Zuordnen: das geänderte Wörterbuch wird nach oben gemeldet")
        } else {
            print("✗ Zuordnen: die Änderung kam nicht oben an")
            fehler += 1
        }

        // Ein späterer Text muss davon profitieren.
        if let gesichert {
            let spaeter = Rueckweg.analysiere("Nochmal UNBEKANNT_3 fragen.", woerterbuch: gesichert)
            if spaeter.offen.isEmpty {
                print("✓ Zuordnen: auch ein späterer Text geht damit auf")
            } else {
                print("✗ Zuordnen: der spätere Text bleibt offen")
                fehler += 1
            }
        }
        return fehler
    }

    /// Jeder Knopf muss jemanden erreichen, und jeder Menüpunkt auch. Ein
    /// Knopf, dessen Ziel den Befehl nicht kennt, tut beim Klicken nichts —
    /// das sieht man erst, wenn man ihn drückt.
    private static func pruefeKnoepfeUndMenue() -> Int {
        var fehler = 0
        let text = "Herr Nyström rief an, Tel. 0621 1234567."

        let schutz = SchutzAnsicht(analyse: Schleuse.analysiere(text, woerterbuch: Woerterbuch()))
        let rueckweg = RueckwegAnsicht(
            ergebnis: Rueckweg.analysiere("Frage an PERSON_1.", woerterbuch: Woerterbuch())
        )
        for ansicht in [schutz as NSView, rueckweg as NSView] {
            let fenster = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            fenster.contentView = ansicht
            fenster.layoutIfNeeded()
            defer { fenster.orderOut(nil) }

            let name = ansicht is SchutzAnsicht ? "Schützen" : "Zurückdrehen"
            if ansicht.acceptsFirstResponder {
                print("✓ Bedienung (\(name)): die Ansicht nimmt den Tastaturfokus an")
            } else {
                print("✗ Bedienung (\(name)): die Ansicht nimmt keinen Fokus — Tastenkürzel wären tot")
                fehler += 1
            }

            let knoepfe = knoepfeSammeln(in: ansicht)
            var lose: [String] = []
            for knopf in knoepfe {
                guard let aktion = knopf.action else {
                    lose.append(knopf.title)
                    continue
                }
                let ziel = knopf.target ?? ansicht
                if !(ziel as AnyObject).responds(to: aktion) { lose.append(knopf.title) }
            }
            if lose.isEmpty {
                print("✓ Bedienung (\(name)): alle \(knoepfe.count) Knöpfe sind verdrahtet")
            } else {
                print("✗ Bedienung (\(name)): ins Leere zeigen \(lose.joined(separator: ", "))")
                fehler += 1
            }
        }

        // Der Rückweg braucht einen Kopier-Knopf: ⏎ allein reicht nicht für
        // alle, die nicht über die Tastatur arbeiten.
        let rueckwegKnoepfe = knoepfeSammeln(in: rueckweg).map(\.title)
        if rueckwegKnoepfe.contains(where: { $0.contains("kopieren") }) {
            print("✓ Bedienung: der Rückweg hat einen Knopf zum Kopieren")
        } else {
            print("✗ Bedienung: im Rückweg fehlt der Kopier-Knopf")
            fehler += 1
        }

        // Und jeder Menüpunkt aus „Aktionen" muss von mindestens einer der
        // beiden Ansichten verstanden werden.
        let menuebefehle = [
            "aktionKategorie:", "aktionVerwerfen:", "aktionZuordnen:",
            "aktionVorigeFundstelle:", "aktionNaechsteFundstelle:", "aktionSuchen:",
            "aktionDecknamenUmschalten:", "aktionLeeren:", "aktionNeuerText:",
            "aktionKopieren:", "aktionKopierenUndMerken:", "aktionNeuerEintrag:",
        ]
        let unverstanden = menuebefehle.filter { name in
            let auswahl = Selector((name))
            return !schutz.responds(to: auswahl) && !rueckweg.responds(to: auswahl)
        }
        if unverstanden.isEmpty {
            print("✓ Bedienung: alle \(menuebefehle.count) Menübefehle kommen an")
        } else {
            print("✗ Bedienung: niemand versteht \(unverstanden.joined(separator: ", "))")
            fehler += 1
        }
        return fehler
    }

    /// Pfeil hoch und runter müssen zwischen den Fundstellen wandern, sobald
    /// die Liste den Fokus hat — und die hat sie von Anfang an.
    private static func pruefePfeiltasten() -> Int {
        var fehler = 0
        let text = """
            Herr Nyström rief an, Frau Weidenbach schrieb,             Rückfragen an a@b.de oder 0621 1234567.
            """
        let analyse = Schleuse.analysiere(text, woerterbuch: Woerterbuch())
        let ansicht = SchutzAnsicht(analyse: analyse)

        // Ein echtes Fenster, das den Fokus annehmen kann.
        let fenster = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        fenster.contentView = ansicht
        fenster.makeKeyAndOrderFront(nil)
        fenster.layoutIfNeeded()
        defer { fenster.orderOut(nil) }

        if ansicht.fokussiereFundstellen() {
            print("✓ Pfeiltasten: der Fokus liegt in der Fundstellenliste")
        } else {
            print("✗ Pfeiltasten: die Liste nimmt den Fokus nicht an")
            fehler += 1
        }

        let ersteAuswahl = ansicht.ausgewaehlterFundFuerPruefung()
        let runter = ansicht.pfeilFuerPruefung(runter: true)
        let zweiteAuswahl = ansicht.ausgewaehlterFundFuerPruefung()

        if runter, ersteAuswahl != zweiteAuswahl, zweiteAuswahl != nil {
            print("✓ Pfeiltasten: ↓ wandert zur nächsten Fundstelle")
        } else {
            print("✗ Pfeiltasten: ↓ bewegt die Auswahl nicht")
            fehler += 1
        }

        _ = ansicht.pfeilFuerPruefung(runter: false)
        if ansicht.ausgewaehlterFundFuerPruefung() == ersteAuswahl {
            print("✓ Pfeiltasten: ↑ wandert zurück")
        } else {
            print("✗ Pfeiltasten: ↑ kommt nicht zurück")
            fehler += 1
        }

        // Und die Ziffer wirkt auf die ausgewählte Stelle, ohne dass man erst
        // im Text markieren muss.
        let vorher = ansicht.analyse.woerterbuch.eintraege.count
        _ = ansicht.tasteFuerPruefung("1")
        if ansicht.analyse.woerterbuch.eintraege.count == vorher + 1 {
            print("✓ Pfeiltasten: 1 wirkt auf die Fundstelle unter dem Fokus")
        } else {
            print("✗ Pfeiltasten: 1 hat nichts bewirkt")
            fehler += 1
        }
        return fehler
    }

    /// Das Hauptfenster darf den Bildschirm nicht ausfüllen. Gemessen wird das
    /// fertige Fenster, nicht der Wunschwert — die gemerkte Größe aus einer
    /// früheren Sitzung könnte ihn überschreiben.
    private static func pruefeFenstergroesse() -> Int {
        var fehler = 0

        // Rechnerisch, mit einem kleinen Bildschirm: 1280 wären dort zu viel.
        let klein = NSRect(x: 0, y: 0, width: 1440, height: 860)
        let passend = Hauptfenster.startgroesse(auf: klein)
        if passend.width <= klein.width - 100 && passend.height <= klein.height - 100 {
            print("✓ Fenstergröße: auf 1440×860 bleibt Rand (\(Int(passend.width))×\(Int(passend.height)))")
        } else {
            print("✗ Fenstergröße: auf 1440×860 zu groß (\(Int(passend.width))×\(Int(passend.height)))")
            fehler += 1
        }

        let winzig = Hauptfenster.startgroesse(auf: NSRect(x: 0, y: 0, width: 700, height: 400))
        if winzig.width >= 1200 {
            print("✓ Fenstergröße: unter die Mindestbreite geht es nicht")
        } else {
            print("✗ Fenstergröße: unter 1200 gerutscht (\(Int(winzig.width)))")
            fehler += 1
        }

        // Und in echt, auf diesem Bildschirm — mit einem geladenen Text, denn
        // erst die Arbeitsfläche bringt ihre eigenen Mindestmaße mit und
        // konnte das Fenster früher auf 1887 Punkte aufblasen.
        let sitzung = Sitzung()
        sitzung.beginne(Schleuse.analysiere(
            "Sehr geehrter Herr Nyström, Ihre IBAN DE89 3704 0044 0532 0130 00 stimmt.",
            woerterbuch: Woerterbuch()
        ))
        let haupt = Hauptfenster(
            woerterbuch: { Woerterbuch() },
            sitzung: sitzung,
            beimSchuetzen: { _, _ in },
            beimZurueckdrehen: { _ in }
        )
        haupt.window?.layoutIfNeeded()
        defer { haupt.close() }
        guard let fenster = haupt.window, let schirm = NSScreen.main else {
            print("✓ Fenstergröße: kein Bildschirm vorhanden, übersprungen")
            return fehler
        }
        let rahmen = fenster.frame
        let sichtbar = schirm.visibleFrame
        if rahmen.width <= sichtbar.width && rahmen.height <= sichtbar.height {
            print("✓ Fenstergröße: \(Int(rahmen.width))×\(Int(rahmen.height)) passt "
                + "auf \(Int(sichtbar.width))×\(Int(sichtbar.height))")
        } else {
            print("✗ Fenstergröße: \(Int(rahmen.width))×\(Int(rahmen.height)) sprengt "
                + "\(Int(sichtbar.width))×\(Int(sichtbar.height))")
            func breit(_ ansicht: NSView, _ tiefe: Int) {
                let w = ansicht.fittingSize.width
                if w > 700 {
                    let titel = (ansicht as? NSTextField)?.stringValue.prefix(40) ?? ""
                    print("   [Diagnose] \(String(repeating: "  ", count: tiefe))\(type(of: ansicht)) \(Int(w)) „\(titel)\"")
                    for kind in ansicht.subviews { breit(kind, tiefe + 1) }
                }
            }
            if let inhalt = fenster.contentView { breit(inhalt, 0) }
            fehler += 1
        }

        // Und es muss sich auch auf ein 13-Zoll-Bild verkleinern lassen. Ein
        // Mindestmaß aus den Constraints würde es wieder aufblasen.
        fenster.setContentSize(NSSize(width: 940, height: 540))
        fenster.layoutIfNeeded()
        let klein13 = fenster.frame
        if klein13.width <= 1220 && klein13.height <= 745 {
            print("✓ Fenstergröße: lässt sich auf \(Int(klein13.width))×\(Int(klein13.height)) stauchen")
        } else {
            print("✗ Fenstergröße: springt auf \(Int(klein13.width))×\(Int(klein13.height)) zurück")
            fehler += 1
        }
        fenster.setContentSize(rahmen.size)

        // Die Wörterbuchspalte darf den Text nicht auffressen.
        fenster.layoutIfNeeded()
        if let spalte = fenster.contentView.flatMap({ woerterbuchSuchen(in: $0) }) {
            let anteil = spalte.frame.width / rahmen.width
            if anteil < 0.38 {
                print("✓ Fenstergröße: Wörterbuch nimmt \(Int(anteil * 100)) % der Breite")
            } else {
                print("✗ Fenstergröße: Wörterbuch nimmt \(Int(anteil * 100)) % der Breite")
                fehler += 1
            }
        }
        return fehler
    }

    /// Das Wörterbuch neben dem Text, wenn es eng wird. Genau hier fiel es
    /// bisher auf die Kopfzeile zusammen: die Ansicht forderte 660 Punkte
    /// Höhe, bekam 360, und eine gebrochene Constraint ließ die Listen auf
    /// null schrumpfen. Sichtbar war dann nur noch „Begriff | Deckname".
    private static func pruefeWoerterbuchBeiEnge() -> Int {
        var fehler = 0

        var buch = Woerterbuch()
        for nummer in 1...97 { _ = buch.anlegen(text: "Person Nummer \(nummer)", kategorie: .person) }

        /// Misst eine eingebaute Ansicht: wie viele Datenzeilen sind zu sehen,
        /// und lässt sich die Liste rollen?
        func miss(_ ort: String, _ ansicht: WoerterbuchAnsicht, _ hoehe: CGFloat) -> Int {
            var schaden = 0
            let tabellen = tabellenSammeln(in: ansicht)
            guard let alle = tabellen.max(by: { $0.numberOfRows < $1.numberOfRows }),
                  let rolle = alle.enclosingScrollView
            else {
                print("✗ Enge (\(ort)): keine Liste gefunden")
                return 1
            }
            let sichtbar = rolle.contentView.bounds.height
            let zeilen = Int(sichtbar / max(1, alle.rowHeight))
            let rollbar = alle.frame.height > sichtbar + 1
            print("   [Diagnose] \(ort): Fläche \(Int(hoehe)) pt, Liste \(Int(sichtbar)) pt "
                + "= \(zeilen) Zeilen, Inhalt \(Int(alle.frame.height)) pt")
            if zeilen >= 4 {
                print("✓ Enge (\(ort)): \(zeilen) Zeilen sichtbar")
            } else {
                print("✗ Enge (\(ort)): nur \(zeilen) Zeilen sichtbar")
                schaden += 1
            }
            if rollbar {
                print("✓ Enge (\(ort)): die Liste lässt sich rollen")
            } else {
                print("✗ Enge (\(ort)): nichts zu rollen, Inhalt passt angeblich ins Bild")
                schaden += 1
            }
            // Rollen können reicht nicht — man muss auch sehen, dass es geht.
            let balkenDa = rolle.verticalScroller.map { !$0.isHidden && $0.frame.width > 0 } ?? false
            if balkenDa {
                print("✓ Enge (\(ort)): der Rollbalken ist sichtbar")
            } else {
                print("✗ Enge (\(ort)): kein sichtbarer Rollbalken")
                schaden += 1
            }
            return schaden
        }

        // Einbauort 1: die Klappe im Popup. Das Popup ist 70 Prozent der
        // Bildschirmhöhe hoch, davon bleibt für die Klappe wenig übrig.
        let popupHoehe: CGFloat = 640
        let ansicht = SchutzAnsicht(analyse: Schleuse.analysiere(
            "Herr Nyström rief an.",
            woerterbuch: buch
        ))
        let popup = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: popupHoehe),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        popup.contentView = ansicht
        ansicht.klappeUmschalten()
        popup.layoutIfNeeded()
        defer { popup.orderOut(nil) }
        if let klappe = woerterbuchSuchen(in: ansicht) {
            fehler += miss("Popup-Klappe", klappe, klappe.frame.height)
        } else {
            print("✗ Enge (Popup-Klappe): nicht aufgeklappt")
            fehler += 1
        }

        // Einbauort 2: die feste Spalte im Hauptfenster, auf Mindestgröße
        // gestaucht.
        let sitzung = Sitzung()
        sitzung.beginne(Schleuse.analysiere("Herr Nyström rief an.", woerterbuch: buch))
        let haupt = Hauptfenster(
            woerterbuch: { buch },
            sitzung: sitzung,
            beimSchuetzen: { _, _ in },
            beimZurueckdrehen: { _ in }
        )
        defer { haupt.close() }
        haupt.window?.setContentSize(NSSize(width: 1200, height: 700))
        haupt.window?.layoutIfNeeded()
        if let spalte = haupt.window?.contentView.flatMap({ woerterbuchSuchen(in: $0) }) {
            fehler += miss("Hauptfenster eng", spalte, spalte.frame.height)
        } else {
            print("✗ Enge (Hauptfenster eng): keine Spalte")
            fehler += 1
        }
        return fehler
    }

    /// Ein Wort im Text korrigieren darf nicht alle Entscheidungen aufheben.
    private static func pruefeKorrekturImText() -> Int {
        var fehler = 0
        let text = "Sally kam. Sally ging. Almut Weidenbach rief an."
        let ansicht = SchutzAnsicht(analyse: Schleuse.analysiere(text, woerterbuch: Woerterbuch()))
        let fenster = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        fenster.contentView = ansicht
        fenster.layoutIfNeeded()
        defer { fenster.orderOut(nil) }

        // Sally verwerfen und danach auf Almut stehen bleiben.
        guard let sally = ansicht.analyse.funde.first(where: { $0.text == "Sally" }),
              let almut = ansicht.analyse.funde.first(where: { $0.text.contains("Almut") })
        else {
            print("✗ Korrektur: Ausgangsfunde fehlen")
            return 1
        }
        ansicht.waehleFundFuerPruefung(sally.id)
        ansicht.aktionVerwerfen(nil)
        ansicht.waehleFundFuerPruefung(almut.id)
        let vorher = ansicht.ausgewaehlterBegriffFuerPruefung()

        // Jetzt hinten ein Wort ergänzen, so wie beim Korrigieren im Text.
        ansicht.setzeTextFuerPruefung("Sally kam. Sally ging. Almut Weidenbach rief zweimal an.")
        ansicht.pruefeJetztFuerPruefung()

        let aktiv = ansicht.analyse.aktiveFunde.map(\.text)
        if !aktiv.contains("Sally") {
            print("✓ Korrektur: das verworfene Sally bleibt draußen")
        } else {
            print("✗ Korrektur: Sally ist wieder da")
            fehler += 1
        }

        let nachher = ansicht.ausgewaehlterBegriffFuerPruefung()
        if nachher == vorher {
            print("✓ Korrektur: die Auswahl bleibt auf „\(nachher ?? "—")\"")
        } else {
            print("✗ Korrektur: Auswahl sprang von „\(vorher ?? "—")\" auf „\(nachher ?? "—")\"")
            fehler += 1
        }
        return fehler
    }

    /// Unbekannte Platzhalter beim Zurückdrehen beiseitelegen.
    private static func pruefeIgnorierenImRueckweg() -> Int {
        var fehler = 0
        let ansicht = RueckwegAnsicht(ergebnis: Rueckweg.analysiere(
            "PERSON_9 traf PERSON_9 und FIRMA_2.",
            woerterbuch: Woerterbuch()
        ))
        let fenster = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        fenster.contentView = ansicht
        fenster.layoutIfNeeded()
        defer { fenster.orderOut(nil) }

        if ansicht.offeneFuerPruefung() == 3 {
            print("✓ Ignorieren: drei offene Platzhalter zu Beginn")
        } else {
            print("✗ Ignorieren: \(ansicht.offeneFuerPruefung()) offene statt 3")
            fehler += 1
        }

        ansicht.waehleFundFuerPruefung(0)
        ansicht.aktionIgnorieren(nil)
        if ansicht.offeneFuerPruefung() == 1 {
            print("✓ Ignorieren: ⌫ legt beide PERSON_9 auf einmal beiseite")
        } else {
            print("✗ Ignorieren: noch \(ansicht.offeneFuerPruefung()) offen statt 1")
            fehler += 1
        }

        // Der Text darf sich dabei nicht ändern — ignoriert heißt stehenlassen.
        if ansicht.ergebnis.ergebnis.contains("PERSON_9") {
            print("✓ Ignorieren: der Platzhalter bleibt im Text stehen")
        } else {
            print("✗ Ignorieren: der Platzhalter verschwand aus dem Text")
            fehler += 1
        }

        ansicht.aktionIgnorieren(nil)
        if ansicht.offeneFuerPruefung() == 3 {
            print("✓ Ignorieren: nochmal ⌫ holt sie zurück")
        } else {
            print("✗ Ignorieren: zurückgeholt sind \(ansicht.offeneFuerPruefung()) offen statt 3")
            fehler += 1
        }
        return fehler
    }

    /// Die Freiliste in den Einstellungen: aufnehmen, entfernen, wirken.
    private static func pruefeFreiliste() -> Int {
        var fehler = 0
        var gemeldet: Woerterbuch?
        let ansicht = FreilisteAnsicht(woerterbuch: Woerterbuch())
        ansicht.beimSichern = { gemeldet = $0 }
        let fenster = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        fenster.contentView = ansicht
        fenster.layoutIfNeeded()
        defer { fenster.orderOut(nil) }

        let anfang = ansicht.zeilenFuerPruefung()
        if anfang.count == Freiliste.eingebaut.count, anfang.allSatisfy(\.eingebaut) {
            print("✓ Freiliste: \(anfang.count) eingebaute Wörter stehen da")
        } else {
            print("✗ Freiliste: \(anfang.count) Zeilen, erwartet \(Freiliste.eingebaut.count) eingebaute")
            fehler += 1
        }

        ansicht.aufnehmenFuerPruefung("Nordlicht")
        if gemeldet?.istFrei("Nordlicht") == true {
            print("✓ Freiliste: aufgenommen und nach oben gemeldet")
        } else {
            print("✗ Freiliste: nichts gemeldet")
            fehler += 1
        }

        // Alphabetisch einsortiert, nicht hinten angehängt.
        let mitNeuem = ansicht.zeilenFuerPruefung().map(\.wort)
        if mitNeuem == mitNeuem.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            print("✓ Freiliste: alphabetisch sortiert")
        } else {
            print("✗ Freiliste: Reihenfolge stimmt nicht")
            fehler += 1
        }

        // Eingebautes lässt sich nicht entfernen.
        ansicht.waehleFuerPruefung("August")
        ansicht.entfernen()
        if ansicht.woerterbuchFuerPruefung().istFrei("August") {
            print("✓ Freiliste: August bleibt — \(ansicht.meldungFuerPruefung())")
        } else {
            print("✗ Freiliste: August ließ sich entfernen")
            fehler += 1
        }

        ansicht.waehleFuerPruefung("Nordlicht")
        ansicht.entfernen()
        if ansicht.woerterbuchFuerPruefung().istFrei("Nordlicht") == false {
            print("✓ Freiliste: eigenes Wort wieder entfernt")
        } else {
            print("✗ Freiliste: Nordlicht blieb stehen")
            fehler += 1
        }

        // Die zuschaltbaren Erkennungen im selben Reiter.
        let haken = ansicht.typenHakenFuerPruefung()
        if haken.count == Zusatzregel.alle.count, haken.allSatisfy({ !$0.an }) {
            print("✓ Typen: \(haken.count) Erkennungen, alle aus")
        } else {
            print("✗ Typen: \(haken.count) Haken, davon \(haken.filter(\.an).count) an")
            fehler += 1
        }

        ansicht.schalteTypFuerPruefung(.website, an: true)
        if gemeldet?.istAn(.website) == true {
            print("✓ Typen: Website angeschaltet und gemeldet")
        } else {
            print("✗ Typen: Website kam nicht oben an")
            fehler += 1
        }

        if let mitWebsite = gemeldet {
            let gefunden = Schleuse.analysiere("Mehr auf www.risiq.de", woerterbuch: mitWebsite)
            if gefunden.aktiveFunde.contains(where: { $0.kategorie == .website }) {
                print("✓ Typen: die Adresse wird sofort gefunden")
            } else {
                print("✗ Typen: die Adresse wird nicht gefunden")
                fehler += 1
            }
        }

        ansicht.schalteTypFuerPruefung(.website, an: false)
        if gemeldet?.istAn(.website) == false {
            print("✓ Typen: und wieder aus")
        } else {
            print("✗ Typen: bleibt an")
            fehler += 1
        }

        // Und die Wirkung auf einen echten Text.
        var buch = Woerterbuch()
        buch.gibFrei("Nordlicht")
        let analyse = Schleuse.analysiere("Sehr geehrter Herr Nordlicht, danke.", woerterbuch: buch)
        if !analyse.aktiveFunde.contains(where: { $0.text == "Nordlicht" }) {
            print("✓ Freiliste: der Begriff wird im Text nicht mehr vorgeschlagen")
        } else {
            print("✗ Freiliste: der Begriff taucht weiter als Fund auf")
            fehler += 1
        }
        return fehler
    }

    /// Die Zuordnungsliste: geclustert, alphabetisch, durchsuchbar.
    private static func pruefeZuordnungsliste() -> Int {
        var fehler = 0
        let eintraege = [
            Eintrag(text: "Zwickel GmbH", kategorie: .firma, nummer: 1),
            Eintrag(text: "info@nordbank.de", kategorie: .email, nummer: 2),
            Eintrag(text: "Thorben Nyström", kategorie: .person, nummer: 3),
            Eintrag(text: "almut@nordbank.de", kategorie: .email, nummer: 4),
            Eintrag(text: "Almut Weidenbach", kategorie: .person, nummer: 5),
        ]
        let waehler = ZuordnungsFenster(
            eintraege: eintraege,
            nennung: "A. Weidenbach",
            vorschlag: nil
        )

        var koepfe: [String] = []
        var namen: [String] = []
        for zeile in waehler.zeilen {
            switch zeile {
            case .kopf(let kategorie, _): koepfe.append(kategorie.anzeigename)
            case .eintrag(let eintrag): namen.append(eintrag.text)
            }
        }
        if koepfe == ["Person", "Firma", "E-Mail"] {
            print("✓ Zuordnen: drei Typblöcke in fester Reihenfolge")
        } else {
            print("✗ Zuordnen: Blöcke sind \(koepfe)")
            fehler += 1
        }
        if namen == ["Almut Weidenbach", "Thorben Nyström", "Zwickel GmbH",
                     "almut@nordbank.de", "info@nordbank.de"] {
            print("✓ Zuordnen: innerhalb der Blöcke alphabetisch")
        } else {
            print("✗ Zuordnen: Reihenfolge ist \(namen)")
            fehler += 1
        }

        // Nach dem Füllen muss eine Eintragszeile stehen, keine Kopfzeile —
        // sonst liefe ⏎ ins Leere.
        if waehler.markierterEintrag?.text == "Almut Weidenbach" {
            print("✓ Zuordnen: die erste Eintragszeile ist vorgewählt")
        } else {
            print("✗ Zuordnen: vorgewählt ist \(waehler.markierterEintrag?.text ?? "nichts")")
            fehler += 1
        }

        waehler.fuelle(suche: "nordbank")
        let gefiltert = waehler.zeilen.compactMap { zeile -> String? in
            if case .eintrag(let eintrag) = zeile { return eintrag.text }
            return nil
        }
        if gefiltert == ["almut@nordbank.de", "info@nordbank.de"] {
            print("✓ Zuordnen: die Suche filtert auf zwei Adressen")
        } else {
            print("✗ Zuordnen: gefiltert bleibt \(gefiltert)")
            fehler += 1
        }
        if waehler.markierterEintrag?.text == "almut@nordbank.de" {
            print("✓ Zuordnen: nach dem Filtern steht die Auswahl auf dem ersten Treffer")
        } else {
            print("✗ Zuordnen: Auswahl nach dem Filtern ist \(waehler.markierterEintrag?.text ?? "nichts")")
            fehler += 1
        }

        waehler.fuelle(suche: "gibtesnicht")
        if waehler.zeilen.isEmpty && waehler.markierterEintrag == nil {
            print("✓ Zuordnen: ohne Treffer bleibt die Liste leer")
        } else {
            print("✗ Zuordnen: ohne Treffer stehen noch \(waehler.zeilen.count) Zeilen")
            fehler += 1
        }
        return fehler
    }

    /// Das Wörterbuch neben dem Text: im Hauptfenster fest, im Popup
    /// ausklappbar. Und was dort gemerkt wird, muss im Text sofort greifen.
    private static func pruefeWoerterbuchDaneben() -> Int {
        var fehler = 0
        let text = "Herr Nyström rief an."

        // Popup: zu, bis man aufklappt.
        let popupAnsicht = SchutzAnsicht(analyse: Schleuse.analysiere(text, woerterbuch: Woerterbuch()))
        let fenster = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1420, height: 760),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        fenster.contentView = popupAnsicht
        fenster.layoutIfNeeded()
        defer { fenster.orderOut(nil) }

        if woerterbuchSuchen(in: popupAnsicht) == nil {
            print("✓ Wörterbuch daneben: im Popup zunächst zugeklappt")
        } else {
            print("✗ Wörterbuch daneben: im Popup schon offen")
            fehler += 1
        }

        popupAnsicht.klappeUmschalten()
        fenster.layoutIfNeeded()
        if woerterbuchSuchen(in: popupAnsicht) != nil {
            print("✓ Wörterbuch daneben: der Knopf klappt es auf")
        } else {
            print("✗ Wörterbuch daneben: der Knopf klappt nichts auf")
            fehler += 1
        }

        popupAnsicht.klappeUmschalten()
        fenster.layoutIfNeeded()
        if woerterbuchSuchen(in: popupAnsicht) == nil {
            print("✓ Wörterbuch daneben: und wieder zu")
        } else {
            print("✗ Wörterbuch daneben: es bleibt offen")
            fehler += 1
        }

        // Hauptfenster: von Anfang an dran — und zwar auch ohne Text, weil es
        // am Fenster hängt und nicht an der Arbeitsfläche.
        let sitzung = Sitzung()
        let haupt = Hauptfenster(
            woerterbuch: { Woerterbuch() },
            sitzung: sitzung,
            beimSchuetzen: { _, _ in },
            beimZurueckdrehen: { _ in }
        )
        haupt.window?.layoutIfNeeded()
        defer { haupt.close() }

        let ohneText = haupt.window?.contentView.flatMap { woerterbuchSuchen(in: $0) }
        if ohneText != nil {
            print("✓ Wörterbuch daneben: im Hauptfenster auch ohne Text sichtbar")
        } else {
            print("✗ Wörterbuch daneben: im Hauptfenster fehlt es")
            fehler += 1
        }

        // Und es bleibt, sobald ein Text dazukommt.
        sitzung.beginne(Schleuse.analysiere(text, woerterbuch: Woerterbuch()))
        haupt.zeigeNeuesten()
        haupt.window?.layoutIfNeeded()
        if haupt.window?.contentView.flatMap({ woerterbuchSuchen(in: $0) }) != nil {
            print("✓ Wörterbuch daneben: bleibt stehen, wenn ein Text kommt")
        } else {
            print("✗ Wörterbuch daneben: verschwindet mit dem Text")
            fehler += 1
        }
        // Zwei Listen: was im Text vorkommt, und alles.
        if let spalte = haupt.window?.contentView.flatMap({ woerterbuchSuchen(in: $0) }) {
            let tabellen = tabellenSammeln(in: spalte)
            if tabellen.count >= 2 {
                print("✓ Wörterbuch daneben: zwei Listen — im Text und alle")
            } else {
                print("✗ Wörterbuch daneben: nur \(tabellen.count) Liste")
                fehler += 1
            }

            var buch = Woerterbuch()
            let eintrag = buch.anlegen(text: "Thorben Nyström", kategorie: .person)
            _ = buch.anlegen(text: "Anna Beispiel", kategorie: .person)
            spalte.setze(woerterbuch: buch)

            // Und mit vielen Einträgen: zeigt die Liste alle oder nur die
            // ersten, die zufällig ins Fenster passen?
            var vieles = Woerterbuch()
            for nummer in 1...40 { _ = vieles.anlegen(text: "Person Nummer \(nummer)", kategorie: .person) }
            spalte.setze(woerterbuch: vieles)
            spalte.setze(imText: [])
            haupt.window?.layoutIfNeeded()
            let alleTabelle = tabellenSammeln(in: spalte).max { $0.numberOfRows < $1.numberOfRows }
            if let alleTabelle, datenzeilen(alleTabelle) == 40 {
                let rolle = alleTabelle.enclosingScrollView
                let sichtbareHoehe = rolle?.contentView.bounds.height ?? 0
                let zeilenSichtbar = Int(sichtbareHoehe / max(1, alleTabelle.rowHeight))
                let spaltenBreite = spalte.frame.width
                let editor = editorSuchen(in: spalte)
                print("   [Diagnose] Fenster \(Int(haupt.window?.frame.width ?? 0))×\(Int(haupt.window?.frame.height ?? 0)) pt, "
                    + "Spalte \(Int(spaltenBreite))×\(Int(spalte.frame.height)) pt, "
                    + "Editor \(Int(editor?.frame.height ?? -1)) (passend \(Int(editor?.fittingSize.height ?? -1))), "
                    + "Liste \(Int(rolle?.frame.width ?? 0))×\(Int(rolle?.frame.height ?? 0)), "
                    + "Ausschnitt \(Int(sichtbareHoehe)) pt = \(zeilenSichtbar) Zeilen, "
                    + "Spaltenbreite in der Tabelle \(Int(alleTabelle.tableColumns.reduce(0) { $0 + $1.width })) pt")
                if zeilenSichtbar >= 12 {
                    print("✓ Wörterbuch daneben: alle 40 Einträge, \(zeilenSichtbar) davon ohne Rollen sichtbar")
                } else {
                    print("✗ Wörterbuch daneben: nur \(zeilenSichtbar) Zeilen passen ins Bild")
                    fehler += 1
                }
            } else {
                print("✗ Wörterbuch daneben: \(alleTabelle.map(datenzeilen) ?? -1) von 40 Einträgen")
                fehler += 1
            }
            spalte.setze(woerterbuch: buch)
            spalte.setze(imText: [])
            haupt.window?.layoutIfNeeded()
            let ohne = tabellenSammeln(in: spalte).map(datenzeilen).sorted()

            spalte.setze(imText: [eintrag.id])
            haupt.window?.layoutIfNeeded()
            let mit = tabellenSammeln(in: spalte).map(datenzeilen).sorted()

            // Drei Tabellen: die beiden Listen und die Schreibweisen im
            // Editor. Geprüft wird deshalb, dass die erwarteten Zahlen
            // vorkommen, nicht an welcher Stelle.
            if ohne.contains(0), ohne.contains(2), mit.contains(1), mit.contains(2) {
                print("✓ Wörterbuch daneben: links nur was im Text steht, rechts alle")
            } else {
                print("✗ Wörterbuch daneben: Zeilen ohne Text \(ohne), mit Text \(mit)")
                fehler += 1
            }
        }
        _ = text
        return fehler
    }

    /// Nach einer Entscheidung muss es zur nächsten offenen Stelle *dahinter*
    /// gehen, nicht zurück an den Anfang.
    private static func pruefeWeiterspringen() -> Int {
        var fehler = 0
        let text = """
            Anna Beispiel schrieb an Bernd Beispiel. Später meldete sich \
            Clara Beispiel, danach Doris Beispiel.
            """
        let analyse = Schleuse.analysiere(text, woerterbuch: Woerterbuch())
        let ansicht = SchutzAnsicht(analyse: analyse)
        let fenster = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        fenster.contentView = ansicht
        fenster.makeKeyAndOrderFront(nil)
        fenster.layoutIfNeeded()
        defer { fenster.orderOut(nil) }

        let offeneAmAnfang = ansicht.analyse.ungeprueft.count
        guard offeneAmAnfang >= 3 else {
            print("✗ Weiterspringen: nur \(offeneAmAnfang) offene Stellen im Probetext")
            return 1
        }

        // Zur zweiten offenen Stelle gehen und sie entscheiden.
        ansicht.fokussiereFundstellen()
        _ = ansicht.pfeilFuerPruefung(runter: true)
        let zweite = ansicht.ausgewaehlterFundFuerPruefung()
        let stelleVorher = ansicht.analyse.funde.first { $0.id == zweite }?.bereich.location ?? -1

        _ = ansicht.tasteFuerPruefung("1")
        ansicht.decknameUebernehmenFuerPruefung()

        let danach = ansicht.ausgewaehlterFundFuerPruefung()
        let stelleDanach = ansicht.analyse.funde.first { $0.id == danach }?.bereich.location ?? -1

        if stelleDanach > stelleVorher {
            print("✓ Weiterspringen: nach ⏎ geht es vorwärts (Zeichen \(stelleVorher) → \(stelleDanach))")
        } else {
            print("✗ Weiterspringen: es geht zurück oder bleibt stehen "
                + "(\(stelleVorher) → \(stelleDanach))")
            fehler += 1
        }

        if ansicht.analyse.funde.first(where: { $0.id == danach })?.brauchtPruefung == true {
            print("✓ Weiterspringen: die neue Stelle ist eine offene")
        } else {
            print("✗ Weiterspringen: gelandet auf einer schon entschiedenen Stelle")
            fehler += 1
        }
        return fehler
    }

    private static func tabellenSammeln(in ansicht: NSView) -> [NSTableView] {
        var gefunden: [NSTableView] = []
        if let tabelle = ansicht as? NSTableView { gefunden.append(tabelle) }
        for unter in ansicht.subviews { gefunden += tabellenSammeln(in: unter) }
        return gefunden
    }

    /// Zeilen ohne die Typköpfe. Seit die Liste nach Typ gruppiert, ist
    /// `numberOfRows` nicht mehr dasselbe wie die Zahl der Einträge.
    private static func datenzeilen(_ tabelle: NSTableView) -> Int {
        let delegat = tabelle.delegate
        return (0..<tabelle.numberOfRows).count { zeile in
            !(delegat?.tableView?(tabelle, isGroupRow: zeile) ?? false)
        }
    }

    /// Die Einstellungen: nimmt das Kurzbefehlfeld eine Kombination an, und
    /// lehnt es die ab, die nicht gehen?
    private static func pruefeEinstellungen() -> Int {
        var fehler = 0
        var aufgenommen: Tastenkombination?
        let feld = Kurzbefehlfeld(.schuetzen)
        feld.beiAufnahme = { aufgenommen = $0 }

        let fenster = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        fenster.contentView = feld
        fenster.layoutIfNeeded()
        defer { fenster.orderOut(nil) }

        // Ohne Zusatztaste: abgelehnt, sonst würde jedes S im System greifen.
        feld.aufnahmeFuerPruefung()
        feld.tasteFuerPruefung(code: UInt16(kVK_ANSI_S), zusatz: [])
        if aufgenommen == nil {
            print("✓ Einstellungen: eine Taste ohne ⌘ ⌥ ⌃ wird abgelehnt")
        } else {
            print("✗ Einstellungen: eine nackte Taste wurde angenommen")
            fehler += 1
        }

        // Mit Zusatztasten: angenommen.
        feld.aufnahmeFuerPruefung()
        feld.tasteFuerPruefung(code: UInt16(kVK_ANSI_J), zusatz: [.command, .option, .control])
        if let aufgenommen, aufgenommen.beschriftung.contains("J") {
            print("✓ Einstellungen: ⌃⌥⌘J wird aufgenommen (\(aufgenommen.beschriftung))")
        } else {
            print("✗ Einstellungen: die Kombination kam nicht an")
            fehler += 1
        }

        // Und sie überlebt den Weg durch die Ablage.
        let gemerkt = Einstellungen.gemeinsam.kurzbefehlSchuetzen
        defer { Einstellungen.gemeinsam.kurzbefehlSchuetzen = gemerkt }
        if let aufgenommen {
            Einstellungen.gemeinsam.kurzbefehlSchuetzen = aufgenommen
            if Einstellungen.gemeinsam.kurzbefehlSchuetzen == aufgenommen {
                print("✓ Einstellungen: der Kurzbefehl übersteht das Speichern")
            } else {
                print("✗ Einstellungen: gespeichert kam etwas anderes zurück")
                fehler += 1
            }
        }

        // Der Seed steht im Fenster, und ein eingefügter Seed kommt oben an.
        let buch = Woerterbuch()
        var gesichert: Woerterbuch?
        let einstellungen = EinstellungenFenster(
            beiKurzbefehlen: {},
            beiDarstellung: { _ in },
            woerterbuch: buch,
            beimWoerterbuch: { gesichert = $0 }
        )
        einstellungen.window?.layoutIfNeeded()
        defer { einstellungen.close() }
        if einstellungen.seedFeldFuerPruefung().stringValue == buch.seed {
            print("✓ Einstellungen: der Seed steht im Fenster")
        } else {
            print("✗ Einstellungen: im Seed-Feld steht „\(einstellungen.seedFeldFuerPruefung().stringValue)\"")
            fehler += 1
        }
        einstellungen.setzeSeedFuerPruefung("  GEMEINSAMER-SEED-VON-DRUEBEN  ")
        if gesichert?.seed == "GEMEINSAMER-SEED-VON-DRUEBEN" {
            print("✓ Einstellungen: ein eingefügter Seed wird gesichert")
        } else {
            print("✗ Einstellungen: der Seed kam nicht an (\(gesichert?.seed ?? "nichts"))")
            fehler += 1
        }
        einstellungen.setzeSeedFuerPruefung("")
        if gesichert?.seed == "GEMEINSAMER-SEED-VON-DRUEBEN" {
            print("✓ Einstellungen: ein leerer Seed wird abgelehnt")
        } else {
            print("✗ Einstellungen: ein leerer Seed ging durch")
            fehler += 1
        }
        return fehler
    }

    private static func woerterbuchSuchen(in ansicht: NSView) -> WoerterbuchAnsicht? {
        if let treffer = ansicht as? WoerterbuchAnsicht { return treffer }
        for unter in ansicht.subviews {
            if let treffer = woerterbuchSuchen(in: unter) { return treffer }
        }
        return nil
    }

    /// Eine zugeschaltete Erkennung muss auch unten als Knopf stehen und auf
    /// ihrer Ziffer liegen — sonst ließe sich eine übersehene Website nur als
    /// „Sonstiges" nachtragen.
    private static func pruefeZusatzKategorien() -> Int {
        var fehler = 0
        var buch = Woerterbuch()
        buch.schalte(.website, an: true)

        let text = "Alles Weitere steht auf unserer Seite Nordlicht."
        let ansicht = SchutzAnsicht(analyse: Schleuse.analysiere(text, woerterbuch: buch))
        let fenster = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        fenster.contentView = ansicht
        fenster.makeKeyAndOrderFront(nil)
        fenster.layoutIfNeeded()
        defer { fenster.orderOut(nil) }

        let titel = knoepfeSammeln(in: ansicht).map(\.title)
        if titel.contains("Website") {
            print("✓ Zusatzkategorien: „Website\" steht als Knopf in der Leiste")
        } else {
            print("✗ Zusatzkategorien: kein Knopf „Website\" in der Leiste (\(titel.joined(separator: ", ")))")
            fehler += 1
        }
        if !titel.contains("Anschrift") {
            print("✓ Zusatzkategorien: „Anschrift\" ist aus und fehlt in der Leiste")
        } else {
            print("✗ Zusatzkategorien: „Anschrift\" steht da, obwohl es aus ist")
            fehler += 1
        }

        ansicht.fokussiereTextFuerPruefung()
        ansicht.markiereFuerPruefung((text as NSString).range(of: "Nordlicht"))
        let abgefangen = ansicht.tasteFuerPruefung("6")
        let angelegt = ansicht.analyse.woerterbuch.eintrag(fuerText: "Nordlicht")
        if abgefangen, angelegt?.kategorie == .website {
            print("✓ Zusatzkategorien: Taste 6 legt die Markierung als Website an")
        } else {
            print("✗ Zusatzkategorien: Taste 6 tut nichts "
                + "(abgefangen: \(abgefangen), Eintrag: \(angelegt?.kategorie.anzeigename ?? "keiner"))")
            fehler += 1
        }

        // Ohne zugeschaltete Erkennung bleibt die 6 eine Ziffer.
        let ohne = SchutzAnsicht(analyse: Schleuse.analysiere(text, woerterbuch: Woerterbuch()))
        fenster.contentView = ohne
        fenster.layoutIfNeeded()
        ohne.fokussiereTextFuerPruefung()
        ohne.markiereFuerPruefung((text as NSString).range(of: "Nordlicht"))
        if ohne.tasteFuerPruefung("6") == false {
            print("✓ Zusatzkategorien: ohne Website-Erkennung ist die 6 keine Kategorie")
        } else {
            print("✗ Zusatzkategorien: die 6 wird abgefangen, obwohl nichts zugeschaltet ist")
            fehler += 1
        }
        return fehler
    }

    /// Der Chip endet mit dem Decknamen. Kein Polster dahinter — sonst sieht
    /// man nicht, ob im Text nach dem Namen ein Leerzeichen kommt oder gleich
    /// das Komma.
    private static func pruefeChipOhnePolster() -> Int {
        let text = "Sehr geehrter Herr Nyström,anbei die Unterlagen."
        let analyse = Schleuse.analysiere(text, woerterbuch: Woerterbuch())
        let aufbau = Chiptext.aufbauen(analyse: analyse, ausgewaehlt: nil)
        guard let fund = analyse.funde.first(where: { $0.text.contains("Nyström") }),
              let bereich = aufbau.bereiche[fund.id]
        else {
            print("✗ Chip: Nyström nicht gefunden")
            return 1
        }
        let anzeige = aufbau.text.string as NSString
        let chip = anzeige.substring(with: bereich)
        let danach = NSMaxRange(bereich) < anzeige.length
            ? anzeige.substring(with: NSRange(location: NSMaxRange(bereich), length: 1))
            : ""
        if chip.hasPrefix("Nyström"), chip.hasSuffix(fund.platzhalter), danach == "," {
            print("✓ Chip: „\(chip)\" endet mit dem Decknamen, das Komma folgt direkt")
            return 0
        }
        print("✗ Chip: „\(chip)\" — danach kommt „\(danach)\" statt des Kommas")
        return 1
    }

    private static func knoepfeSammeln(in ansicht: NSView) -> [NSButton] {
        var gefunden: [NSButton] = []
        if let knopf = ansicht as? NSButton { gefunden.append(knopf) }
        for unter in ansicht.subviews { gefunden += knoepfeSammeln(in: unter) }
        return gefunden
    }

    private static func segmentSuchen(in ansicht: NSView) -> NSSegmentedControl? {
        if let treffer = ansicht as? NSSegmentedControl { return treffer }
        for unter in ansicht.subviews {
            if let treffer = segmentSuchen(in: unter) { return treffer }
        }
        return nil
    }

    private static func rueckwegflaecheSuchen(in ansicht: NSView) -> RueckwegAnsicht? {
        if let treffer = ansicht as? RueckwegAnsicht { return treffer }
        for unter in ansicht.subviews {
            if let treffer = rueckwegflaecheSuchen(in: unter) { return treffer }
        }
        return nil
    }

    private static func schutzflaecheSuchen(in ansicht: NSView) -> SchutzAnsicht? {
        if let treffer = ansicht as? SchutzAnsicht { return treffer }
        for unter in ansicht.subviews {
            if let treffer = schutzflaecheSuchen(in: unter) { return treffer }
        }
        return nil
    }

    private static func suchfeldSuchen(in ansicht: NSView) -> NSSearchField? {
        if let treffer = ansicht as? NSSearchField { return treffer }
        for unter in ansicht.subviews {
            if let treffer = suchfeldSuchen(in: unter) { return treffer }
        }
        return nil
    }

    private static func editorSuchen(in ansicht: NSView) -> EintragEditor? {
        if let treffer = ansicht as? EintragEditor { return treffer }
        for unter in ansicht.subviews {
            if let treffer = editorSuchen(in: unter) { return treffer }
        }
        return nil
    }

    private static func suchzeileSuchen(in ansicht: NSView) -> Textsuche? {
        if let treffer = ansicht as? Textsuche { return treffer }
        for unter in ansicht.subviews {
            if let treffer = suchzeileSuchen(in: unter) { return treffer }
        }
        return nil
    }

    private static func rollflaecheSuchen(in ansicht: NSView) -> NSScrollView? {
        if let rolle = ansicht as? NSScrollView, rolle.documentView is NSTextView { return rolle }
        for unter in ansicht.subviews {
            if let treffer = rollflaecheSuchen(in: unter) { return treffer }
        }
        return nil
    }

    private static func tabelleSuchen(in ansicht: NSView) -> NSTableView? {
        if let tabelle = ansicht as? NSTableView { return tabelle }
        for unter in ansicht.subviews {
            if let treffer = tabelleSuchen(in: unter) { return treffer }
        }
        return nil
    }

    private static func pruefeKurzbefehl() -> Int {
        let einstellungen = Einstellungen.gemeinsam
        var fehler = 0

        for (name, kombination) in [
            ("Schützen", einstellungen.kurzbefehlSchuetzen),
            ("Zurückdrehen", einstellungen.kurzbefehlRueckweg),
        ] {
            if Kurzbefehle.gemeinsam.registriere(kombination, aktion: {}) != nil {
                print("✓ Kurzbefehl \(name): \(kombination.beschriftung) ist frei und angemeldet")
            } else {
                print("✗ Kurzbefehl \(name): \(kombination.beschriftung) ist von einem "
                    + "anderen Programm belegt")
                fehler += 1
            }
        }
        Kurzbefehle.gemeinsam.entferneAlle()
        return fehler
    }
}
