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
