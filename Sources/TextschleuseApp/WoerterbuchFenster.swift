import AppKit
import TextschleuseCore

/// Liste aller gemerkten Begriffe. Aliase stehen eingerückt unter ihrer
/// Hauptnennung.
///
/// Was hier fehlt und in der nächsten Ausbaustufe dazukommt: Suchfeld,
/// Zusammenlegen per Ziehen und das Bearbeiten der Schreibweise.
final class WoerterbuchFenster: NSWindowController {

    private static var offen: WoerterbuchFenster?

    private var woerterbuch: Woerterbuch
    private let beimSichern: (Woerterbuch) -> Void
    private let beimExportieren: (URL, Woerterbuch) throws -> Void

    private let tabelle = NSTableView()
    private let zaehler = NSTextField(labelWithString: "")

    /// Flachgeklopfte Darstellung: Hauptnennung, danach ihre Aliase.
    private struct Zeile {
        var eintragId: UUID
        var istAlias: Bool
        var text: String
        var platzhalter: String
        var kategorie: String
        var herkunft: String
    }

    private var zeilen: [Zeile] = []

    static func zeige(
        woerterbuch: Woerterbuch,
        beimSichern: @escaping (Woerterbuch) -> Void,
        beimExportieren: @escaping (URL, Woerterbuch) throws -> Void
    ) {
        offen?.close()
        let fenster = WoerterbuchFenster(
            woerterbuch: woerterbuch,
            beimSichern: beimSichern,
            beimExportieren: beimExportieren
        )
        offen = fenster
        fenster.showWindow(nil)
        fenster.window?.makeKeyAndOrderFront(nil)
    }

    init(
        woerterbuch: Woerterbuch,
        beimSichern: @escaping (Woerterbuch) -> Void,
        beimExportieren: @escaping (URL, Woerterbuch) throws -> Void
    ) {
        self.woerterbuch = woerterbuch
        self.beimSichern = beimSichern
        self.beimExportieren = beimExportieren

        let fenster = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        fenster.title = "Mein Wörterbuch"
        fenster.center()
        super.init(window: fenster)

        baueOberflaeche()
        aktualisiere()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }

    private func baueOberflaeche() {
        for (kennung, titel, breite) in [
            ("text", "Begriff", 260.0),
            ("platzhalter", "Platzhalter", 130.0),
            ("kategorie", "Typ", 120.0),
            ("herkunft", "Herkunft", 150.0),
        ] {
            let spalte = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(kennung))
            spalte.title = titel
            spalte.width = breite
            tabelle.addTableColumn(spalte)
        }
        tabelle.dataSource = self
        tabelle.delegate = self
        tabelle.usesAlternatingRowBackgroundColors = true
        tabelle.allowsMultipleSelection = true

        let rollflaeche = NSScrollView()
        rollflaeche.documentView = tabelle
        rollflaeche.hasVerticalScroller = true
        rollflaeche.borderType = .bezelBorder

        zaehler.font = .systemFont(ofSize: 11)
        zaehler.textColor = .secondaryLabelColor

        let loeschen = NSButton(title: "Löschen", target: self, action: #selector(loescheAuswahl))
        let autoLeeren = NSButton(
            title: "Automatisch erkannte leeren",
            target: self,
            action: #selector(leereAutomatische)
        )
        let exportieren = NSButton(title: "Klartext-Export …", target: self, action: #selector(exportiere))
        for knopf in [loeschen, autoLeeren, exportieren] {
            knopf.bezelStyle = .rounded
            knopf.controlSize = .regular
        }

        let knopfleiste = NSStackView(views: [loeschen, autoLeeren, exportieren, NSView(), zaehler])
        knopfleiste.orientation = .horizontal
        knopfleiste.spacing = 8

        let hinweis = NSTextField(labelWithString:
            "Gelöschte Nummern werden nicht neu vergeben. Der Klartext-Export ist unverschlüsselt.")
        hinweis.font = .systemFont(ofSize: 11)
        hinweis.textColor = .secondaryLabelColor

        let stapel = NSStackView(views: [rollflaeche, knopfleiste, hinweis])
        stapel.orientation = .vertical
        stapel.spacing = 10
        stapel.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        window?.contentView = stapel

        rollflaeche.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rollflaeche.leadingAnchor.constraint(equalTo: stapel.leadingAnchor, constant: 16),
            rollflaeche.trailingAnchor.constraint(equalTo: stapel.trailingAnchor, constant: -16),
        ])
    }

    private func aktualisiere() {
        zeilen = woerterbuch.eintraege
            .sorted { ($0.kategorie.praefix, $0.nummer) < ($1.kategorie.praefix, $1.nummer) }
            .flatMap { eintrag -> [Zeile] in
                let haupt = Zeile(
                    eintragId: eintrag.id,
                    istAlias: false,
                    text: eintrag.text,
                    platzhalter: eintrag.platzhalter,
                    kategorie: eintrag.kategorie.anzeigename,
                    herkunft: eintrag.automatischErkannt ? "automatisch erkannt" : "gemerkt"
                )
                let aliase = eintrag.aliase.map { alias in
                    Zeile(
                        eintragId: eintrag.id,
                        istAlias: true,
                        text: "↳ \(alias.text)",
                        platzhalter: eintrag.platzhalter(fuer: alias),
                        kategorie: eintrag.kategorie.anzeigename,
                        herkunft: "Schreibweise"
                    )
                }
                return [haupt] + aliase
            }

        let anzahl = woerterbuch.eintraege.count
        let automatisch = woerterbuch.eintraege.filter(\.automatischErkannt).count
        zaehler.stringValue = "\(anzahl) Einträge, davon \(automatisch) automatisch erkannt"
        tabelle.reloadData()
    }

    private func sichere() {
        beimSichern(woerterbuch)
        aktualisiere()
    }

    // MARK: Aktionen

    @objc private func loescheAuswahl() {
        let betroffen = Set(tabelle.selectedRowIndexes.compactMap { zeilen[$0].eintragId })
        guard !betroffen.isEmpty else { return }

        let meldung = NSAlert()
        meldung.messageText = betroffen.count == 1
            ? "Diesen Eintrag löschen?"
            : "\(betroffen.count) Einträge löschen?"
        meldung.informativeText =
            "Die Nummern bleiben verbrannt. Texte, die du schon verschickt hast, lassen sich damit nicht mehr zurückdrehen."
        meldung.addButton(withTitle: "Löschen")
        meldung.addButton(withTitle: "Abbrechen")
        guard meldung.runModal() == .alertFirstButtonReturn else { return }

        for kennung in betroffen { woerterbuch.loeschen(kennung) }
        sichere()
    }

    @objc private func leereAutomatische() {
        let meldung = NSAlert()
        meldung.messageText = "Automatisch erkannte Einträge löschen?"
        meldung.informativeText =
            "Betrifft E-Mail-Adressen, Telefonnummern, IBANs und Ähnliches. Antworten auf ältere Texte lassen sich danach nicht mehr zurückdrehen."
        meldung.addButton(withTitle: "Löschen")
        meldung.addButton(withTitle: "Abbrechen")
        guard meldung.runModal() == .alertFirstButtonReturn else { return }

        woerterbuch.automatischErkannteLoeschen()
        sichere()
    }

    @objc private func exportiere() {
        let meldung = NSAlert()
        meldung.messageText = "Export im Klartext"
        meldung.informativeText =
            "Die Datei ist unverschlüsselt und enthält echte Namen, Adressen und Bankdaten. Jeder, der sie öffnet, liest alles."
        meldung.addButton(withTitle: "Fortfahren")
        meldung.addButton(withTitle: "Abbrechen")
        guard meldung.runModal() == .alertFirstButtonReturn else { return }

        let auswahl = NSSavePanel()
        auswahl.nameFieldStringValue = "textschleuse-woerterbuch.json"
        auswahl.allowedContentTypes = [.json]
        guard auswahl.runModal() == .OK, let ziel = auswahl.url else { return }

        do {
            try beimExportieren(ziel, woerterbuch)
        } catch {
            let fehler = NSAlert()
            fehler.messageText = "Der Export ist fehlgeschlagen"
            fehler.informativeText = error.localizedDescription
            fehler.runModal()
        }
    }
}

extension WoerterbuchFenster: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { zeilen.count }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard let spalte = tableColumn?.identifier.rawValue, zeilen.indices.contains(row) else {
            return nil
        }
        let zeile = zeilen[row]
        let inhalt: String
        switch spalte {
        case "text": inhalt = zeile.text
        case "platzhalter": inhalt = zeile.platzhalter
        case "kategorie": inhalt = zeile.kategorie
        default: inhalt = zeile.herkunft
        }

        let feld = NSTextField(labelWithString: inhalt)
        feld.font = spalte == "platzhalter"
            ? .monospacedSystemFont(ofSize: 11, weight: .regular)
            : .systemFont(ofSize: 12)
        feld.textColor = zeile.istAlias ? .secondaryLabelColor : .labelColor
        feld.lineBreakMode = .byTruncatingTail
        return feld
    }
}
