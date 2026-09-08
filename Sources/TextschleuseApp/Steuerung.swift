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
            beimZurueckdrehen: { text in Zwischenablage.schreib(text) }
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

        do {
            try speicher.sichern(woerterbuch)
        } catch {
            zeigeFehler("Das Wörterbuch ließ sich nicht speichern", error)
            return
        }

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
        offenesPopup = popup
        popup.zeige()
    }

    // MARK: Menüeinträge

    @objc func zeigeWoerterbuch() {
        NSApp.activate(ignoringOtherApps: true)
        WoerterbuchFenster.zeige(
            woerterbuch: woerterbuch,
            beimSichern: { [weak self] geaendert in
                self?.woerterbuch = geaendert
                try? self?.speicher.sichern(geaendert)
            },
            beimExportieren: { [weak self] ziel, buch in
                try self?.speicher.exportiereKlartext(buch, nach: ziel)
            }
        )
    }

    @objc func zeigeEinstellungen() {
        NSApp.activate(ignoringOtherApps: true)
        let einstellungen = Einstellungen.gemeinsam

        let nurLeiste = NSButton(checkboxWithTitle: "Nur in der Menüleiste, kein Dock-Symbol", target: nil, action: nil)
        nurLeiste.state = einstellungen.nurMenueleiste ? .on : .off
        let hinweise = NSButton(checkboxWithTitle: "KI-Hinweis mitkopieren", target: nil, action: nil)
        hinweise.state = einstellungen.hinweiseMitkopieren ? .on : .off
        hinweise.toolTip = "Ein paar Zeilen vor dem Text mit der Bitte, die Platzhalter stehen zu lassen."

        let stapel = NSStackView(views: [nurLeiste, hinweise])
        stapel.orientation = .vertical
        stapel.alignment = .leading
        stapel.spacing = 6
        stapel.frame = NSRect(x: 0, y: 0, width: 340, height: 50)

        let meldung = NSAlert()
        meldung.messageText = "Einstellungen"
        meldung.informativeText = """
            Kurzbefehle: \(einstellungen.kurzbefehlSchuetzen.beschriftung) zum Schützen, \
            \(einstellungen.kurzbefehlRueckweg.beschriftung) zum Zurückdrehen. Sie lassen sich \
            in dieser Ausbaustufe noch nicht ändern.

            Das Popup öffnet sich \(einstellungen.popupPosition.anzeigename.lowercased()).
            """
        meldung.accessoryView = stapel
        meldung.addButton(withTitle: "Übernehmen")
        meldung.addButton(withTitle: "Abbrechen")
        guard meldung.runModal() == .alertFirstButtonReturn else { return }

        einstellungen.hinweiseMitkopieren = hinweise.state == .on
        let neuNurLeiste = nurLeiste.state == .on
        guard neuNurLeiste != einstellungen.nurMenueleiste else { return }
        einstellungen.nurMenueleiste = neuNurLeiste
        NSApp.setActivationPolicy(neuNurLeiste ? .accessory : .regular)
        if !neuNurLeiste { zeigeHauptfenster() }
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
