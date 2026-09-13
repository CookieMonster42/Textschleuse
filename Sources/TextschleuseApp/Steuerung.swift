import AppKit
import TextschleuseCore

/// Hält alles zusammen: Menüleistensymbol, Kurzbefehle, Wörterbuch und die
/// beiden Popups.
final class Steuerung: NSObject, NSApplicationDelegate {

    private var statusSymbol: NSStatusItem?
    private let speicher = Speicher()
    private var woerterbuch = Woerterbuch()

    /// Die Texte dieser Sitzung. Nur im Arbeitsspeicher — dauerhaft
    /// gespeichert wird allein das Wörterbuch.
    private let sitzung = Sitzung()

    private var offenesPopup: NSWindow?

    func applicationDidFinishLaunching(_ meldung: Notification) {
        ladeWoerterbuch()
        baueHauptmenue()
        baueMenueleiste()
        meldeKurzbefehleAn()
        NSApp.setActivationPolicy(Einstellungen.gemeinsam.nurMenueleiste ? .accessory : .regular)
        if !Einstellungen.gemeinsam.nurMenueleiste { zeigeHauptfenster() }
    }

    /// Beim Klick aufs Dock-Symbol das Fenster wieder aufmachen.
    func applicationShouldHandleReopen(_ anwendung: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { zeigeHauptfenster() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ anwendung: NSApplication) -> Bool {
        // Nein: die App lebt in der Menüleiste weiter, damit die Kurzbefehle
        // greifen. Beenden geht über das Menü.
        false
    }

    func applicationWillTerminate(_ meldung: Notification) {
        Kurzbefehle.gemeinsam.entferneAlle()
    }

    // MARK: Start

    private func ladeWoerterbuch() {
        do {
            woerterbuch = try speicher.laden()
        } catch {
            let meldung = NSAlert()
            meldung.messageText = "Das Wörterbuch ließ sich nicht laden"
            meldung.informativeText = error.localizedDescription
            meldung.addButton(withTitle: "Mit leerem Wörterbuch starten")
            meldung.addButton(withTitle: "Beenden")
            if meldung.runModal() == .alertSecondButtonReturn {
                NSApp.terminate(nil)
            }
            woerterbuch = Woerterbuch()
        }
    }

    private func baueMenueleiste() {
        // Ein altes Symbol vorher wegräumen: sonst steht nach dem Ändern
        // eines Kurzbefehls ein zweites in der Menüleiste.
        if let altes = statusSymbol { NSStatusBar.system.removeStatusItem(altes) }
        let symbol = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        symbol.button?.image = Menuesymbol.zeichnen()
        symbol.button?.image?.isTemplate = true
        symbol.button?.toolTip = "Textschleuse"

        let menue = NSMenu()
        let einstellungen = Einstellungen.gemeinsam

        let schuetzen = NSMenuItem(
            title: "Text schützen  \(einstellungen.kurzbefehlSchuetzen.beschriftung)",
            action: #selector(schuetzeZwischenablage),
            keyEquivalent: ""
        )
        schuetzen.target = self
        menue.addItem(schuetzen)

        let zurueck = NSMenuItem(
            title: "Zurückdrehen  \(einstellungen.kurzbefehlRueckweg.beschriftung)",
            action: #selector(dreheZurueck),
            keyEquivalent: ""
        )
        zurueck.target = self
        menue.addItem(zurueck)

        menue.addItem(.separator())

        let fenster = NSMenuItem(
            title: "Fenster zeigen",
            action: #selector(zeigeHauptfenster),
            keyEquivalent: ""
        )
        fenster.target = self
        menue.addItem(fenster)

        menue.addItem(.separator())

        let woerterbuchEintrag = NSMenuItem(
            title: "Wörterbuch …",
            action: #selector(zeigeWoerterbuch),
            keyEquivalent: ""
        )
        woerterbuchEintrag.target = self
        menue.addItem(woerterbuchEintrag)

        let einstellungenEintrag = NSMenuItem(
            title: "Einstellungen …",
            action: #selector(zeigeEinstellungen),
            keyEquivalent: ""
        )
        einstellungenEintrag.target = self
        menue.addItem(einstellungenEintrag)

        menue.addItem(.separator())
        let beenden = NSMenuItem(title: "Beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menue.addItem(beenden)

        symbol.menu = menue
        statusSymbol = symbol
    }

    private func meldeKurzbefehleAn() {
        let einstellungen = Einstellungen.gemeinsam
        var nichtVerfuegbar: [String] = []

        if Kurzbefehle.gemeinsam.registriere(einstellungen.kurzbefehlSchuetzen, aktion: { [weak self] in
            self?.schuetzeZwischenablage()
        }) == nil {
            nichtVerfuegbar.append(einstellungen.kurzbefehlSchuetzen.beschriftung)
        }

        if Kurzbefehle.gemeinsam.registriere(einstellungen.kurzbefehlRueckweg, aktion: { [weak self] in
            self?.dreheZurueck()
        }) == nil {
            nichtVerfuegbar.append(einstellungen.kurzbefehlRueckweg.beschriftung)
        }

        guard !nichtVerfuegbar.isEmpty else { return }
        let meldung = NSAlert()
        meldung.messageText = "Kurzbefehl belegt"
        meldung.informativeText = """
            \(nichtVerfuegbar.joined(separator: " und ")) ist schon von einem anderen \
            Programm belegt. Wähle in den Einstellungen eine andere Kombination.
            """
        meldung.runModal()
    }

    /// Wirft ein noch offenes Popup weg. Nichts davon wandert ins Wörterbuch —
    /// wer den Kurzbefehl neu drückt, will den alten Text nicht mehr.
    private func schliesseOffenes() {
        offenesPopup?.orderOut(nil)
        offenesPopup = nil
    }

    // MARK: Hauptfenster

    @objc func zeigeHauptfenster() {
        Hauptfenster.zeige(
            woerterbuch: { [weak self] in self?.woerterbuch ?? Woerterbuch() },
            sitzung: sitzung,
            beimSchuetzen: { [weak self] analyse, merken in
                self?.uebernimmSchutz(analyse, merken: merken)
            },
            beimZurueckdrehen: { text in Zwischenablage.schreib(text) },
            beimWoerterbuch: { [weak self] geaendert in self?.uebernimmWoerterbuch(geaendert) }
        )
    }

    /// Das Menü oben am Bildschirm. Ohne das gäbe es kein ⌘V, kein ⌘C und
    /// keinen Weg, die App über die Oberfläche zu beenden.
    private func baueHauptmenue() {
        let leiste = NSMenu()

        let programm = NSMenuItem()
        let programmMenue = NSMenu()
        programmMenue.addItem(withTitle: "Über Textschleuse", action: #selector(zeigeUeber), keyEquivalent: "")
            .target = self
        programmMenue.addItem(.separator())
        programmMenue.addItem(withTitle: "Einstellungen …", action: #selector(zeigeEinstellungen), keyEquivalent: ",")
            .target = self
        programmMenue.addItem(withTitle: "Wörterbuch …", action: #selector(zeigeWoerterbuch), keyEquivalent: "d")
            .target = self
        programmMenue.addItem(
            withTitle: "Aus Sicherung wiederherstellen …",
            action: #selector(stelleAusSicherungWiederHer),
            keyEquivalent: ""
        ).target = self
        programmMenue.addItem(.separator())
        programmMenue.addItem(
            withTitle: "Textschleuse ausblenden",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        programmMenue.addItem(.separator())
        programmMenue.addItem(
            withTitle: "Textschleuse beenden",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        programm.submenu = programmMenue
        leiste.addItem(programm)

        let ablage = NSMenuItem()
        let ablageMenue = NSMenu(title: "Ablage")
        ablageMenue.addItem(withTitle: "Fenster zeigen", action: #selector(zeigeHauptfenster), keyEquivalent: "0")
            .target = self
        ablageMenue.addItem(
            withTitle: "Zwischenablage schützen",
            action: #selector(schuetzeZwischenablage),
            keyEquivalent: "s"
        ).target = self
        ablageMenue.addItem(
            withTitle: "Zwischenablage zurückdrehen",
            action: #selector(dreheZurueck),
            keyEquivalent: "r"
        ).target = self
        ablageMenue.addItem(.separator())
        ablageMenue.addItem(withTitle: "Fenster schließen", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        ablage.submenu = ablageMenue
        leiste.addItem(ablage)

        leiste.addItem(baueAktionenmenue())

        // Ohne dieses Menü gibt es kein Einfügen per Tastatur. AppKit hängt
        // die Befehle an die Menüeinträge, nicht an die Textfelder.
        let bearbeiten = NSMenuItem()
        let bearbeitenMenue = NSMenu(title: "Bearbeiten")
        // Ohne Ziel: der Befehl wandert die Antwortkette hinunter bis zu dem,
        // der ihn versteht. In der Schutzansicht ist das ihr eigener Verlauf.
        bearbeitenMenue.addItem(withTitle: "Widerrufen", action: Selector(("undo:")), keyEquivalent: "z")
        let wiederholen = bearbeitenMenue.addItem(
            withTitle: "Wiederholen",
            action: Selector(("redo:")),
            keyEquivalent: "z"
        )
        wiederholen.keyEquivalentModifierMask = [.command, .shift]
        bearbeitenMenue.addItem(.separator())
        for (titel, aktion, taste) in [
            ("Ausschneiden", #selector(NSText.cut(_:)), "x"),
            ("Kopieren", #selector(NSText.copy(_:)), "c"),
            ("Einfügen", #selector(NSText.paste(_:)), "v"),
            ("Alles auswählen", #selector(NSText.selectAll(_:)), "a"),
        ] {
            bearbeitenMenue.addItem(withTitle: titel, action: aktion, keyEquivalent: taste)
        }
        bearbeiten.submenu = bearbeitenMenue
        leiste.addItem(bearbeiten)

        let fensterMenue = NSMenu(title: "Fenster")
        let fenster = NSMenuItem()
        fenster.submenu = fensterMenue
        leiste.addItem(fenster)

        NSApp.mainMenu = leiste
        NSApp.windowsMenu = fensterMenue
    }

    /// Alles, was in den Arbeitsflächen geht, auch als Menüpunkt.
    ///
    /// Ohne Ziel eingetragen: der Befehl wandert die Antwortkette hinunter zu
    /// der Ansicht, die gerade vorn ist. Das ist der Grund, warum die
    /// Kurzbefehle jetzt auch dann greifen, wenn der Fokus auf einem Knopf
    /// oder in der Liste sitzt — vorher hörte nur das Textfeld zu.
    private func baueAktionenmenue() -> NSMenuItem {
        let aktionen = NSMenuItem()
        let menue = NSMenu(title: "Aktionen")

        for (index, kategorie) in Kategorie.schnellwahl.enumerated() {
            let eintrag = menue.addItem(
                withTitle: "Als \(kategorie.anzeigename) schützen",
                action: Selector(("aktionKategorie:")),
                keyEquivalent: "\(index + 1)"
            )
            eintrag.tag = index
        }
        menue.addItem(.separator())

        let mitTaste: [(String, String, NSEvent.ModifierFlags)] = [
            ("Verwerfen", "aktionVerwerfen:", []),
            ("Gehört zu …", "aktionZuordnen:", [.command]),
        ]
        for (titel, name, zusatz) in mitTaste {
            let eintrag = menue.addItem(withTitle: titel, action: Selector((name)), keyEquivalent: "")
            if name == "aktionZuordnen:" {
                eintrag.keyEquivalent = "d"
                eintrag.keyEquivalentModifierMask = zusatz
            }
        }
        menue.addItem(.separator())

        let vorige = menue.addItem(
            withTitle: "Vorige Fundstelle",
            action: Selector(("aktionVorigeFundstelle:")),
            keyEquivalent: String(UnicodeScalar(NSUpArrowFunctionKey)!)
        )
        vorige.keyEquivalentModifierMask = [.option]
        let naechste = menue.addItem(
            withTitle: "Nächste Fundstelle",
            action: Selector(("aktionNaechsteFundstelle:")),
            keyEquivalent: String(UnicodeScalar(NSDownArrowFunctionKey)!)
        )
        naechste.keyEquivalentModifierMask = [.option]

        menue.addItem(.separator())
        menue.addItem(withTitle: "Im Text suchen", action: Selector(("aktionSuchen:")), keyEquivalent: "f")
        let klappe = menue.addItem(
            withTitle: "Wörterbuch neben dem Text",
            action: Selector(("aktionWoerterbuchKlappe:")),
            keyEquivalent: "d"
        )
        klappe.keyEquivalentModifierMask = [.command, .option]
        menue.addItem(
            withTitle: "Decknamen im Text ein- und ausblenden",
            action: Selector(("aktionDecknamenUmschalten:")),
            keyEquivalent: "e"
        )
        menue.addItem(withTitle: "Leeren", action: Selector(("aktionLeeren:")), keyEquivalent: "")
        menue.addItem(
            withTitle: "Neuer Text aus der Zwischenablage",
            action: Selector(("aktionNeuerText:")),
            keyEquivalent: "n"
        )

        menue.addItem(.separator())
        let kopieren = menue.addItem(
            withTitle: "Ergebnis kopieren",
            action: Selector(("aktionKopieren:")),
            keyEquivalent: "\r"
        )
        kopieren.keyEquivalentModifierMask = [.command]
        let kopierenMerken = menue.addItem(
            withTitle: "Kopieren und alles merken",
            action: Selector(("aktionKopierenUndMerken:")),
            keyEquivalent: "\r"
        )
        kopierenMerken.keyEquivalentModifierMask = [.command, .shift]

        menue.addItem(.separator())
        menue.addItem(
            withTitle: "Platzhalter zuordnen …",
            action: Selector(("aktionZuordnen:")),
            keyEquivalent: ""
        )
        menue.addItem(
            withTitle: "Platzhalter als neuen Eintrag …",
            action: Selector(("aktionNeuerEintrag:")),
            keyEquivalent: ""
        )

        aktionen.submenu = menue
        return aktionen
    }

    @objc private func zeigeUeber() {
        NSApp.activate(ignoringOtherApps: true)
        let meldung = NSAlert()
        meldung.messageText = "Textschleuse"
        meldung.informativeText = """
            Ersetzt Namen, Adressen und Bankdaten durch Platzhalter, bevor der Text             in ein KI-Tool geht — und dreht die Antwort wieder zurück.

            Alles bleibt auf diesem Rechner. Es geht nichts ins Netz.

            risiq intern
            """
        meldung.runModal()
    }

    // MARK: Schützen

    @objc func schuetzeZwischenablage() {
        // Ein noch offenes Popup wird geschlossen, nicht nach vorn geholt.
        // Der Kurzbefehl heißt: nimm, was jetzt in der Zwischenablage liegt.
        schliesseOffenes()

        // Das Popup geht immer auf, auch wenn nichts gefunden wurde und auch
        // bei leerer Zwischenablage. Ein Fenster, das sich von selbst wieder
        // schließt, lässt dich im Ungewissen, ob der Kurzbefehl überhaupt
        // angekommen ist — und nimmt dir die Möglichkeit, selbst zu markieren.
        let analyse = Schleuse.analysiere(Zwischenablage.lies() ?? "", woerterbuch: woerterbuch)

        // Der Vorgang steht ab jetzt in der Sitzung, auch wenn nie kopiert
        // wird. Das Hauptfenster zeigt damit, was hier gerade passiert.
        let kennung = sitzung.beginne(analyse)
        let popup = SchutzPopup(analyse: analyse) { [weak self] ausgang in
            self?.offenesPopup = nil
            guard case .uebernommen(let fertig, let merken) = ausgang else { return }
            self?.uebernimmSchutz(fertig, merken: merken)
        }
        popup.beiAenderung = { [weak self] stand in
            self?.sitzung.aktualisiere(kennung, mit: stand)
        }
        offenesPopup = popup
        popup.zeige()
    }

    private func uebernimmSchutz(_ analyse: Analyse, merken: Bool) {
        var endstand = analyse
        if merken {
            // ⌘⏎: alle noch offenen Vermutungen so ins Wörterbuch übernehmen,
            // wie die Heuristik sie eingeschätzt hat.
            for fund in endstand.ungeprueft {
                Schleuse.bestaetige(fundId: fund.id, als: fund.kategorie, in: &endstand)
            }
        }

        let hatDateiVorher = speicher.hatDatei
        woerterbuch = endstand.woerterbuch
        if let laufender = sitzung.neuester?.id {
            sitzung.aktualisiere(laufender, mit: endstand)
        } else {
            sitzung.beginne(endstand)
        }

        Zwischenablage.schreib(Schleuse.fuerZwischenablage(
            endstand,
            mitHinweisen: Einstellungen.gemeinsam.hinweiseMitkopieren
        ))

        guard sichereWoerterbuch(woerterbuch) else { return }

        if !hatDateiVorher { frageNachBackup() }
    }

    // MARK: Rückweg

    @objc func dreheZurueck() {
        schliesseOffenes()
        let ergebnis = Rueckweg.analysiere(
            Zwischenablage.lies() ?? "",
            woerterbuch: woerterbuch,
            unbekannte: sitzung.unbekannte
        )

        let popup = RueckwegPopup(
            ergebnis: ergebnis,
            woerterbuch: woerterbuch,
            unbekannte: sitzung.unbekannte
        ) { [weak self] ausgang in
            self?.offenesPopup = nil
            guard case .uebernommen(let fertig) = ausgang else { return }
            Zwischenablage.schreib(fertig)
        }
        popup.beiWoerterbuchAenderung = { [weak self] geaendert in
            self?.uebernimmWoerterbuch(geaendert)
        }
        offenesPopup = popup
        popup.zeige()
    }

    /// Nimmt ein geändertes Wörterbuch an und schreibt es weg. Eine Zuordnung
    /// im Rückweg wäre sonst beim nächsten Text wieder verloren.
    private func uebernimmWoerterbuch(_ geaendert: Woerterbuch) {
        // Erst schreiben, dann übernehmen: wird die Rückfrage abgelehnt, soll
        // auch der Stand im Speicher der alte bleiben.
        guard sichereWoerterbuch(geaendert) else { return }
        woerterbuch = geaendert
    }

    // MARK: Menüeinträge

    @objc func zeigeWoerterbuch() {
        NSApp.activate(ignoringOtherApps: true)
        WoerterbuchFenster.zeige(
            woerterbuch: woerterbuch,
            beimSichern: { [weak self] geaendert in
                guard self?.sichereWoerterbuch(geaendert) == true else { return }
                self?.woerterbuch = geaendert
            },
            beimExportieren: { [weak self] ziel, buch in
                try self?.speicher.exportiereKlartext(buch, nach: ziel)
            }
        )
    }

    @objc func zeigeEinstellungen() {
        EinstellungenFenster.zeige(
            beiKurzbefehlen: { [weak self] in self?.meldeKurzbefehleNeuAn() },
            beiDarstellung: { [weak self] nurLeiste in
                NSApp.setActivationPolicy(nurLeiste ? .accessory : .regular)
                if !nurLeiste { self?.zeigeHauptfenster() }
            },
            woerterbuch: woerterbuch,
            beimWoerterbuch: { [weak self] geaendert in
                guard self?.sichereWoerterbuch(geaendert) == true else { return }
                self?.woerterbuch = geaendert
            }
        )
    }

    /// Nach einer Änderung in den Einstellungen: alte Anmeldungen weg, neue
    /// hin. Ohne das Abmelden bliebe die alte Kombination aktiv.
    private func meldeKurzbefehleNeuAn() {
        Kurzbefehle.gemeinsam.entferneAlle()
        meldeKurzbefehleAn()
        baueMenueleiste()
    }

    // MARK: Backup

    /// Ohne den Schlüssel aus der Keychain ist die Datei nicht mehr lesbar.
    /// Deshalb einmalig zum Klartext-Export auffordern, direkt nach dem ersten
    /// Speichern.
    private func frageNachBackup() {
        guard !Einstellungen.gemeinsam.backupAufgefordert else { return }
        Einstellungen.gemeinsam.backupAufgefordert = true

        NSApp.activate(ignoringOtherApps: true)
        let meldung = NSAlert()
        meldung.messageText = "Jetzt ein Backup anlegen?"
        meldung.informativeText = """
            Das Wörterbuch liegt verschlüsselt auf der Platte, der Schlüssel in der \
            Keychain. Geht der Schlüssel verloren, etwa bei einem Rechnerwechsel, sind \
            die Einträge weg.

            Ein Backup ist unverschlüsselt und enthält echte Namen und Bankdaten. Leg es \
            dorthin, wo du auch andere vertrauliche Dateien hinlegst.
            """
        meldung.addButton(withTitle: "Backup anlegen …")
        meldung.addButton(withTitle: "Später")
        guard meldung.runModal() == .alertFirstButtonReturn else { return }

        let auswahl = NSSavePanel()
        auswahl.nameFieldStringValue = "textschleuse-woerterbuch.json"
        auswahl.allowedContentTypes = [.json]
        auswahl.message = "Unverschlüsseltes Backup des Wörterbuchs"
        guard auswahl.runModal() == .OK, let ziel = auswahl.url else { return }

        do {
            try speicher.exportiereKlartext(woerterbuch, nach: ziel)
            Einstellungen.gemeinsam.backupPfad = ziel
        } catch {
            zeigeFehler("Das Backup ließ sich nicht schreiben", error)
        }
    }

    /// Der einzige Weg, auf dem das Wörterbuch auf die Platte kommt.
    ///
    /// Schrumpft der Bestand drastisch, fragt der Speicher zurück statt zu
    /// schreiben. Das ist aus einem Verlust entstanden: 97 Einträge wurden
    /// klaglos durch eine Handvoll ersetzt, und ohne Sicherung war das nicht
    /// mehr zu holen.
    @discardableResult
    func sichereWoerterbuch(_ buch: Woerterbuch) -> Bool {
        do {
            try speicher.sichern(buch)
            return true
        } catch let fehler as SpeicherFehler {
            guard case .wuerdeSchrumpfen(let vorher, let nachher) = fehler else {
                zeigeFehler("Das Wörterbuch ließ sich nicht speichern", fehler)
                return false
            }
            NSApp.activate(ignoringOtherApps: true)
            let frage = NSAlert()
            frage.messageText = "Der Bestand schrumpft von \(vorher) auf \(nachher) Einträge"
            frage.informativeText = """
                Wenn du gerade nichts Größeres gelöscht hast, ist das ein Fehler. \
                Abbrechen lässt die Datei unangetastet.

                Die letzten Stände liegen unter „Wörterbuch › Aus Sicherung \
                wiederherstellen …".
                """
            frage.alertStyle = .critical
            frage.addButton(withTitle: "Abbrechen")
            frage.addButton(withTitle: "Trotzdem speichern")
            guard frage.runModal() == .alertSecondButtonReturn else { return false }
            do {
                try speicher.sichern(buch, auchWennKleiner: true)
                return true
            } catch {
                zeigeFehler("Das Wörterbuch ließ sich nicht speichern", error)
                return false
            }
        } catch {
            zeigeFehler("Das Wörterbuch ließ sich nicht speichern", error)
            return false
        }
    }

    /// Holt einen früheren Stand zurück. Zeigt vorher, was drinsteht.
    @objc func stelleAusSicherungWiederHer() {
        NSApp.activate(ignoringOtherApps: true)
        let staende = speicher.sicherungen()
        guard !staende.isEmpty else {
            let leer = NSAlert()
            leer.messageText = "Es gibt noch keine Sicherungen"
            leer.informativeText = "Ab dieser Version legt jedes Speichern eine an, unter "
                + speicher.sicherungsordner.path
            leer.runModal()
            return
        }

        let auswahl = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 380, height: 25))
        for pfad in staende {
            let anzahl = (try? speicher.lieseSicherung(pfad).eintraege.count).map { "\($0) Einträge" }
                ?? "unlesbar"
            auswahl.addItem(withTitle: "\(pfad.lastPathComponent) — \(anzahl)")
            auswahl.lastItem?.representedObject = pfad
        }

        let frage = NSAlert()
        frage.messageText = "Aus Sicherung wiederherstellen"
        frage.informativeText = "Der jetzige Stand (\(woerterbuch.eintraege.count) Einträge) "
            + "wird vorher selbst als Sicherung abgelegt."
        frage.accessoryView = auswahl
        frage.addButton(withTitle: "Wiederherstellen")
        frage.addButton(withTitle: "Abbrechen")
        guard frage.runModal() == .alertFirstButtonReturn,
              let pfad = auswahl.selectedItem?.representedObject as? URL
        else { return }

        do {
            let alt = try speicher.lieseSicherung(pfad)
            try speicher.sichern(alt, auchWennKleiner: true)
            woerterbuch = alt
            let fertig = NSAlert()
            fertig.messageText = "Wiederhergestellt"
            fertig.informativeText = "\(alt.eintraege.count) Einträge aus "
                + pfad.lastPathComponent + "."
            fertig.runModal()
        } catch {
            zeigeFehler("Die Sicherung ließ sich nicht lesen", error)
        }
    }

    private func zeigeFehler(_ titel: String, _ fehler: Error) {
        let meldung = NSAlert()
        meldung.messageText = titel
        meldung.informativeText = fehler.localizedDescription
        meldung.alertStyle = .warning
        meldung.runModal()
    }
}

/// Das Menüleistensymbol: zwei waagerechte Striche mit einem Riegel dazwischen.
/// Als Schablonenbild gezeichnet, damit es sich Hell und Dunkel anpasst.
enum Menuesymbol {

    static func zeichnen() -> NSImage {
        let groesse = NSSize(width: 17, height: 15)
        let bild = NSImage(size: groesse, flipped: false) { rahmen in
            let strich = NSBezierPath()
            strich.lineWidth = 1.6
            strich.lineCapStyle = .round

            // Zulauf oben, Ablauf unten.
            strich.move(to: NSPoint(x: rahmen.minX + 1.5, y: rahmen.maxY - 3))
            strich.line(to: NSPoint(x: rahmen.maxX - 1.5, y: rahmen.maxY - 3))
            strich.move(to: NSPoint(x: rahmen.minX + 1.5, y: rahmen.minY + 3))
            strich.line(to: NSPoint(x: rahmen.maxX - 1.5, y: rahmen.minY + 3))
            NSColor.black.setStroke()
            strich.stroke()

            // Der Riegel in der Mitte.
            let riegel = NSBezierPath(roundedRect: NSRect(
                x: rahmen.midX - 3.2,
                y: rahmen.midY - 2.4,
                width: 6.4,
                height: 4.8
            ), xRadius: 1.4, yRadius: 1.4)
            NSColor.black.setFill()
            riegel.fill()
            return true
        }
        bild.isTemplate = true
        return bild
    }
}
