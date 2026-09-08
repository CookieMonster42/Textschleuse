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

        print("")
        print(fehler == 0 ? "Alles in Ordnung." : "\(fehler) Punkt(e) fehlgeschlagen.")
        exit(fehler == 0 ? 0 : 1)
    }

    private static func pruefeKeychain() -> Int {
        let ordner = FileManager.default.temporaryDirectory
            .appendingPathComponent("textschleuse-selbsttest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: ordner) }

        let speicher = Speicher(ordner: ordner)
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
        let fenster = WoerterbuchFenster(
            woerterbuch: buch,
            beimSichern: { gesichert = $0 },
            beimExportieren: { _, _ in }
        )
        fenster.window?.layoutIfNeeded()
        defer { fenster.close() }

        guard let inhalt = fenster.window?.contentView else {
            print("✗ Wörterbuch: das Fenster hat keinen Inhalt")
            return 1
        }

        var fehler = 0

        // Liste: zwei Einträge, einer davon mit Schreibweise, macht drei Zeilen.
        let tabelle = tabelleSuchen(in: inhalt)
        if tabelle?.numberOfRows == 3 {
            print("✓ Wörterbuch: 3 Zeilen, Schreibweise eingerückt unter der Hauptnennung")
        } else {
            print("✗ Wörterbuch: \(tabelle?.numberOfRows ?? -1) Zeilen statt 3")
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
        fenster.waehle(person.id)
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
            fenster.filterGeaendert()
            let saetze = beschriftungenSammeln(in: inhalt)
            if saetze.contains(where: { $0.contains("PERSON_1 ist Thorben Nyström") }) {
                print("✓ Wörterbuch: Deckname nachschlagen zeigt den Klartext")
            } else {
                print("✗ Wörterbuch: die Auflösungszeile fehlt")
                fehler += 1
            }

            feld.stringValue = "GIBTESNICHT"
            fenster.filterGeaendert()
            let danach = beschriftungenSammeln(in: inhalt)
            if !danach.contains(where: { $0.contains(" ist ") && $0.contains("Nyström") }) {
                print("✓ Wörterbuch: ohne Treffer bleibt die Zeile weg")
            } else {
                print("✗ Wörterbuch: die Auflösungszeile steht ohne Treffer da")
                fehler += 1
            }
            feld.stringValue = ""
            fenster.filterGeaendert()
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

    /// Das Hauptfenster: gibt es beide Reiter, ein Eingabefeld, und wird aus
    /// eingefügtem Text eine Arbeitsfläche?
    private static func pruefeHauptfenster() -> Int {
        var fehler = 0
        var buch = Woerterbuch()
        var gesichert: Analyse?

        let fenster = Hauptfenster(
            woerterbuch: { buch },
            sitzung: Sitzung(),
            beimSchuetzen: { analyse, _ in gesichert = analyse },
            beimZurueckdrehen: { _ in }
        )
        fenster.window?.layoutIfNeeded()
        defer { fenster.close() }

        guard let inhalt = fenster.window?.contentView else {
            print("✗ Hauptfenster: kein Inhalt")
            return 1
        }

        let reiter = reiterSuchen(in: inhalt)
        if reiter?.numberOfTabViewItems == 2 {
            print("✓ Hauptfenster: zwei Reiter, Schützen und Zurückdrehen")
        } else {
            print("✗ Hauptfenster: \(reiter?.numberOfTabViewItems ?? -1) Reiter statt 2")
            fehler += 1
        }

        // Ohne Text darf keine Arbeitsfläche entstehen.
        if schutzflaecheSuchen(in: inhalt) == nil {
            print("✓ Hauptfenster: startet mit dem Eingabefeld, nicht mit einer leeren Fläche")
        } else {
            print("✗ Hauptfenster: die Arbeitsfläche steht schon vor der Eingabe da")
            fehler += 1
        }

        // Text einfügen und prüfen lassen.
        guard let eingabe = eingabeSuchen(in: inhalt) else {
            print("✗ Hauptfenster: kein Eingabefeld gefunden")
            return fehler + 1
        }
        eingabe.setzeText("Herr Nyström schrieb an almut@example.org.")
        eingabe.loeseAus()
        fenster.window?.layoutIfNeeded()

        guard let flaeche = schutzflaecheSuchen(in: inhalt) else {
            print("✗ Hauptfenster: nach dem Prüfen kommt keine Arbeitsfläche")
            return fehler + 1
        }
        if flaeche.analyse.funde.isEmpty {
            print("✗ Hauptfenster: die Arbeitsfläche hat keine Fundstellen")
            fehler += 1
        } else {
            print("✓ Hauptfenster: aus eingefügtem Text wird eine Arbeitsfläche "
                + "mit \(flaeche.analyse.funde.count) Fundstellen")
        }

        // Übernehmen muss nach oben gemeldet werden.
        flaeche.uebernehmen(merken: false)
        if gesichert != nil {
            print("✓ Hauptfenster: Übernehmen meldet das Ergebnis nach oben")
        } else {
            print("✗ Hauptfenster: Übernehmen kam nicht an")
            fehler += 1
        }

        _ = buch
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
        fenster.layoutIfNeeded()
        defer { fenster.orderOut(nil) }

        // Ohne Markierung darf die Ziffer nicht abgefangen werden.
        if ansicht.tasteFuerPruefung("1") == false {
            print("✓ Ziffern: ohne Markierung tippt die 1 eine Eins")
        } else {
            print("✗ Ziffern: ohne Markierung wird die 1 abgefangen")
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

    private static func reiterSuchen(in ansicht: NSView) -> NSTabView? {
        if let treffer = ansicht as? NSTabView { return treffer }
        for unter in ansicht.subviews {
            if let treffer = reiterSuchen(in: unter) { return treffer }
        }
        return nil
    }

    private static func eingabeSuchen(in ansicht: NSView) -> Eingabeflaeche? {
        if let treffer = ansicht as? Eingabeflaeche, treffer.window != nil || treffer.superview != nil {
            return treffer
        }
        for unter in ansicht.subviews {
            if let treffer = eingabeSuchen(in: unter) { return treffer }
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
