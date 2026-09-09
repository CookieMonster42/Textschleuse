import AppKit
import TextschleuseCore

/// Das Wörterbuch als Ansicht: oben die Liste mit Suchfeld, darunter der
/// Editor für den ausgewählten Eintrag.
///
/// Steht als eigene Ansicht da, weil sie an drei Stellen gebraucht wird: im
/// eigenen Fenster, dauerhaft im Hauptfenster und ausklappbar im Popup.
final class WoerterbuchAnsicht: NSView {

    private var woerterbuch: Woerterbuch
    private let beimSichern: (Woerterbuch) -> Void
    private let beimExportieren: (URL, Woerterbuch) throws -> Void

    private let tabelle = NSTableView()
    fileprivate let editor = EintragEditor()
    private let zaehler = NSTextField(labelWithString: "")
    private let suchfeld = NSSearchField()
    private let aufloesungZeile = NSTextField(wrappingLabelWithString: "")

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
    /// Bleibt über einen Neuaufbau der Liste hinweg erhalten, damit der Editor
    /// nach jeder Änderung denselben Eintrag zeigt.
    fileprivate var ausgewaehlt: UUID?


    /// `schmal` heißt: Liste und Editor untereinander statt nebeneinander.
    /// Für die Spalte im Hauptfenster und die Klappe im Popup.
    private let schmal: Bool

    init(
        woerterbuch: Woerterbuch,
        schmal: Bool = false,
        beimSichern: @escaping (Woerterbuch) -> Void,
        beimExportieren: @escaping (URL, Woerterbuch) throws -> Void
    ) {
        self.woerterbuch = woerterbuch
        self.schmal = schmal
        self.beimSichern = beimSichern
        self.beimExportieren = beimExportieren
        super.init(frame: NSRect(x: 0, y: 0, width: schmal ? 340 : 980, height: 560))

        baueOberflaeche()
        aktualisiere()
    }

    /// Nimmt einen neuen Stand von außen an — etwa wenn im Popup gerade ein
    /// Eintrag entstanden ist.
    func setze(woerterbuch neues: Woerterbuch) {
        woerterbuch = neues
        aktualisiere()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }

    private func baueOberflaeche() {
        for (kennung, titel, breite) in [
            ("text", "Begriff", 220.0),
            ("platzhalter", "Deckname", 130.0),
            ("kategorie", "Typ", 100.0),
            ("herkunft", "Herkunft", 120.0),
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
        rollflaeche.translatesAutoresizingMaskIntoConstraints = false

        editor.translatesAutoresizingMaskIntoConstraints = false
        editor.beiBefehl = { [weak self] befehl in self?.fuehreAus(befehl) }

        suchfeld.placeholderString = "Begriff oder Deckname, etwa PERSON_3"
        suchfeld.target = self
        suchfeld.action = #selector(gefiltert)
        suchfeld.sendsWholeSearchString = false
        suchfeld.sendsSearchStringImmediately = true
        suchfeld.translatesAutoresizingMaskIntoConstraints = false

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
        }

        let knopfleiste = NSStackView(views: [loeschen, autoLeeren, exportieren, NSView(), zaehler])
        knopfleiste.orientation = .horizontal
        knopfleiste.spacing = 8
        knopfleiste.translatesAutoresizingMaskIntoConstraints = false

        let hinweis = NSTextField(labelWithString:
            "Gelöschte Nummern werden nicht neu vergeben. Der Klartext-Export ist unverschlüsselt.")
        hinweis.font = .systemFont(ofSize: 11)
        hinweis.textColor = .secondaryLabelColor

        aufloesungZeile.font = .systemFont(ofSize: 12)
        aufloesungZeile.isHidden = true

        let links = NSStackView(views: [suchfeld, aufloesungZeile, rollflaeche])
        links.orientation = .vertical
        links.spacing = 8
        links.translatesAutoresizingMaskIntoConstraints = false

        let mitte = NSStackView(views: [links, editor])
        mitte.orientation = schmal ? .vertical : .horizontal
        mitte.spacing = schmal ? 10 : 16
        mitte.distribution = .fill
        mitte.translatesAutoresizingMaskIntoConstraints = false

        let stapel = NSStackView(views: [mitte, knopfleiste, hinweis])
        stapel.orientation = .vertical
        stapel.spacing = 10
        stapel.alignment = .leading
        stapel.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stapel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stapel)
        NSLayoutConstraint.activate([
            stapel.topAnchor.constraint(equalTo: topAnchor),
            stapel.leadingAnchor.constraint(equalTo: leadingAnchor),
            stapel.trailingAnchor.constraint(equalTo: trailingAnchor),
            stapel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        knopfleiste.setContentHuggingPriority(.required, for: .vertical)
        hinweis.setContentHuggingPriority(.required, for: .vertical)
        mitte.setContentHuggingPriority(.defaultLow, for: .vertical)
        mitte.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        NSLayoutConstraint.activate([
            mitte.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -32),
            mitte.heightAnchor.constraint(greaterThanOrEqualToConstant: schmal ? 300 : 380),
            knopfleiste.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -32),
            suchfeld.widthAnchor.constraint(equalTo: links.widthAnchor),
            schmal
                ? editor.widthAnchor.constraint(equalTo: mitte.widthAnchor)
                : editor.widthAnchor.constraint(equalToConstant: 340),
        ])
    }

    // MARK: Darstellung

    private func aktualisiere() {
        let filter = suchfeld.stringValue.trimmingCharacters(in: .whitespaces).lowercased()

        zeilen = woerterbuch.eintraege
            .filter { eintrag in
                guard !filter.isEmpty else { return true }
                return eintrag.text.lowercased().contains(filter)
                    || eintrag.aliase.contains { $0.text.lowercased().contains(filter) }
                    // Alle Decknamen, auch die von Schreibweisen und die
                    // früheren — sonst findest du nicht, was in einer alten
                    // Mail steht.
                    || eintrag.alleDecknamen.contains { $0.lowercased().contains(filter) }
            }
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
        zaehler.stringValue = filter.isEmpty
            ? "\(anzahl) Einträge, davon \(automatisch) automatisch erkannt"
            : "\(Set(zeilen.map(\.eintragId)).count) von \(anzahl) Einträgen"

        beschrifteAufloesung()
        tabelle.reloadData()
        stelleAuswahlWiederHer()
        editor.zeige(ausgewaehlt.flatMap { woerterbuch.eintrag(mitId: $0) })
    }

    /// Die Antwort auf „wer war nochmal PERSON_3?" in einem Satz, direkt über
    /// der Liste. Erscheint nur, wenn die Eingabe wirklich ein Deckname ist.
    private func beschrifteAufloesung() {
        guard let treffer = woerterbuch.aufloesen(suchfeld.stringValue) else {
            // Auch den Text leeren, nicht nur ausblenden: eine versteckte
            // Beschriftung mit altem Inhalt ist eine Falle.
            aufloesungZeile.stringValue = ""
            aufloesungZeile.isHidden = true
            return
        }

        var satz = "\(suchfeld.stringValue.uppercased()) ist \(treffer.klartext)"
        if treffer.alias != nil {
            satz += " — eine Schreibweise von \(treffer.eintrag.text)"
        }
        if treffer.istFrueherer {
            satz += ". Früherer Deckname, heute heißt der Eintrag \(treffer.eintrag.platzhalter)"
        }
        aufloesungZeile.stringValue = satz + "."
        aufloesungZeile.textColor = treffer.istFrueherer ? .secondaryLabelColor : .labelColor
        aufloesungZeile.isHidden = false
    }

    private func stelleAuswahlWiederHer() {
        guard let ausgewaehlt,
              let index = zeilen.firstIndex(where: { $0.eintragId == ausgewaehlt && !$0.istAlias })
        else { return }
        tabelle.selectRowIndexes([index], byExtendingSelection: false)
    }

    private func sichere() {
        beimSichern(woerterbuch)
        aktualisiere()
    }

    // MARK: Befehle aus dem Editor

    /// Führt aus, was der Editor meldet. Rückgabe `nil` heißt: hat geklappt.
    private func fuehreAus(_ befehl: EintragEditor.Befehl) -> String? {
        guard let kennung = ausgewaehlt else { return nil }
        do {
            switch befehl {
            case .begriff(let text):
                try woerterbuch.aendereText(kennung, auf: text)
            case .kategorie(let kategorie):
                woerterbuch.aendereKategorie(kennung, auf: kategorie)
            case .deckname(let name):
                _ = try woerterbuch.umbenennen(kennung, auf: name)
            case .decknameZuruecksetzen:
                woerterbuch.decknameZuruecksetzen(kennung)
            case .aliasNeu(let text):
                guard woerterbuch.aliasHinzufuegen(text, zu: kennung) != nil else {
                    return "Diese Schreibweise gibt es schon."
                }
            case .aliasText(let aliasId, let text):
                try woerterbuch.aendereAlias(aliasId, in: kennung, auf: text)
            case .aliasLoeschen(let aliasId):
                woerterbuch.loescheAlias(aliasId, in: kennung)
            case .aliasHauptnennung(let aliasId):
                woerterbuch.machtZurHauptnennung(aliasId, in: kennung)
            }
        } catch {
            // Nichts wurde geändert; die Meldung geht zurück in den Editor.
            aktualisiere()
            return error.localizedDescription
        }
        sichere()
        return nil
    }

    // MARK: Aktionen

    @objc private func gefiltert() { aktualisiere() }

    /// Wie `gefiltert`, aber von außen aufrufbar. Das Suchfeld meldet sich bei
    /// programmgesteuerter Eingabe nicht von selbst.
    func filterGeaendert() { aktualisiere() }

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
        if let ausgewaehlt, betroffen.contains(ausgewaehlt) { self.ausgewaehlt = nil }
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
        ausgewaehlt = nil
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

extension WoerterbuchAnsicht: NSTableViewDataSource, NSTableViewDelegate {

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

    func tableViewSelectionDidChange(_ meldung: Notification) {
        guard zeilen.indices.contains(tabelle.selectedRow) else {
            waehle(nil)
            return
        }
        waehle(zeilen[tabelle.selectedRow].eintragId)
    }
}

extension WoerterbuchAnsicht {

    /// Wählt einen Eintrag aus und zeigt ihn im Editor.
    ///
    /// Steht hier und nicht nur im Delegaten, weil `selectRowIndexes` die
    /// Benachrichtigung nicht in jedem Fall auslöst. Wer die Auswahl
    /// programmgesteuert setzt — der Selbsttest etwa —, ruft das hier.
    func waehle(_ kennung: UUID?) {
        ausgewaehlt = kennung
        editor.zeige(kennung.flatMap { woerterbuch.eintrag(mitId: $0) })
    }
}
