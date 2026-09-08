import AppKit
import TextschleuseCore

/// Hält alles zusammen: Menüleistensymbol, Kurzbefehle, Wörterbuch und die
/// beiden Popups.
final class Steuerung: NSObject, NSApplicationDelegate {

    private var statusSymbol: NSStatusItem?
    private let speicher = Speicher()
    private var woerterbuch = Woerterbuch()

    /// Die Zuordnung `UNBEKANNT_n` → Klartext des letzten Vorgangs. Nur im
    /// Arbeitsspeicher, damit nach dem Beenden nichts zurückbleibt.
    private var letzteUnbekannte: [String: String] = [:]

    private var offenesPopup: NSWindow?

    func applicationDidFinishLaunching(_ meldung: Notification) {
        ladeWoerterbuch()
        baueMenueleiste()
        meldeKurzbefehleAn()
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

    // MARK: Schützen

    @objc private func schuetzeZwischenablage() {
        // Ein noch offenes Popup wird geschlossen, nicht nach vorn geholt.
        // Der Kurzbefehl heißt: nimm, was jetzt in der Zwischenablage liegt.
        schliesseOffenes()
        guard let text = Zwischenablage.lies() else {
            KurzInfo.zeige("In der Zwischenablage steht kein Text.")
            return
        }

        let analyse = Schleuse.analysiere(text, woerterbuch: woerterbuch)
        guard !analyse.funde.isEmpty else {
            KurzInfo.zeige("Nichts gefunden. Der Text bleibt, wie er ist.")
            return
        }

        let popup = SchutzPopup(analyse: analyse) { [weak self] ausgang in
            self?.offenesPopup = nil
            guard case .uebernommen(let fertig, let merken) = ausgang else { return }
            self?.uebernimmSchutz(fertig, merken: merken)
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
        letzteUnbekannte = endstand.unbekannte

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

    @objc private func dreheZurueck() {
        schliesseOffenes()
        guard let text = Zwischenablage.lies() else {
            KurzInfo.zeige("In der Zwischenablage steht kein Text.")
            return
        }

        let ergebnis = Rueckweg.analysiere(
            text,
            woerterbuch: woerterbuch,
            unbekannte: letzteUnbekannte
        )
        guard !ergebnis.funde.isEmpty else {
            KurzInfo.zeige("Keine Platzhalter im Text gefunden.")
            return
        }

        let popup = RueckwegPopup(ergebnis: ergebnis) { [weak self] ausgang in
            self?.offenesPopup = nil
            guard case .uebernommen(let fertig) = ausgang else { return }
            Zwischenablage.schreib(fertig)
        }
        offenesPopup = popup
        popup.zeige()
    }

    // MARK: Menüeinträge

    @objc private func zeigeWoerterbuch() {
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

    @objc private func zeigeEinstellungen() {
        NSApp.activate(ignoringOtherApps: true)
        let meldung = NSAlert()
        meldung.messageText = "Einstellungen kommen in der nächsten Ausbaustufe"
        meldung.informativeText = """
            Kurzbefehle: \(Einstellungen.gemeinsam.kurzbefehlSchuetzen.beschriftung) zum Schützen, \
            \(Einstellungen.gemeinsam.kurzbefehlRueckweg.beschriftung) zum Zurückdrehen. \
            Popup öffnet sich \(Einstellungen.gemeinsam.popupPosition.anzeigename.lowercased()).
            """
        meldung.runModal()
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
