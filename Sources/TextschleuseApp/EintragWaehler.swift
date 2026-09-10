import AppKit
import TextschleuseCore

/// Fragt, zu welchem bekannten Eintrag eine Nennung gehört.
///
/// Der Fall: „Jan Maia" steht im Wörterbuch, im Text steht „Jan  Maia" mit
/// zwei Leerzeichen oder „J. Maia". Die Automatik hält das für jemand anderen.
/// Hier sagst du, dass es dieselbe Person ist — sie bekommt dann `PERSON_3B`
/// statt eines eigenen Eintrags, und beim Lesen der KI-Antwort bleibt klar,
/// dass beides zusammengehört.
///
/// Früher stand hier ein Aufklappmenü mit allen Einträgen hintereinander. Ab
/// dem dritten Dutzend findet man darin nichts mehr. Jetzt: Suchfeld oben,
/// darunter nach Typ geclustert und alphabetisch.
enum EintragWaehler {

    /// Zeigt die Auswahl und liefert den gewählten Eintrag, oder `nil` bei
    /// Abbruch.
    static func frage(
        woerterbuch: Woerterbuch,
        fuer nennung: String,
        vorschlag: UUID?
    ) -> Eintrag? {
        guard !woerterbuch.eintraege.isEmpty else {
            let leer = NSAlert()
            leer.messageText = "Das Wörterbuch ist noch leer"
            leer.informativeText = "Merke zuerst einen Eintrag, dann kannst du weitere "
                + "Schreibweisen daran hängen."
            leer.runModal()
            return nil
        }

        let fenster = ZuordnungsFenster(
            eintraege: woerterbuch.eintraege,
            nennung: nennung,
            vorschlag: vorschlag
        )
        return fenster.frageAb()
    }
}

/// Das modale Fenster hinter `EintragWaehler`. Eigene Klasse, weil eine
/// Tabelle mit Kopfzeilen, Suche und Tastaturbedienung in einer
/// `NSAlert`-Beiwagenansicht nicht mehr unterzubringen ist.
final class ZuordnungsFenster: NSObject, NSTableViewDataSource, NSTableViewDelegate,
    NSSearchFieldDelegate, NSWindowDelegate {

    /// Eine Zeile der Tabelle: entweder ein Typ-Kopf oder ein Eintrag.
    enum Zeile {
        case kopf(Kategorie, Int)
        case eintrag(Eintrag)
    }

    private let alle: [Eintrag]
    private let nennung: String
    private let vorschlag: UUID?

    private let fenster: NSPanel
    private let suchfeld = NSSearchField()
    private let tabelle = NSTableView()
    private let zaehler = NSTextField(labelWithString: "")
    private let zuordnenKnopf: NSButton

    private(set) var zeilen: [Zeile] = []
    private var gewaehlt: Eintrag?

    init(eintraege: [Eintrag], nennung: String, vorschlag: UUID?) {
        alle = eintraege
        self.nennung = nennung
        self.vorschlag = vorschlag
        fenster = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        zuordnenKnopf = NSButton(title: "Zuordnen", target: nil, action: nil)
        super.init()
        baueAuf()
        fuelle(suche: "")
        waehleVorschlag()
    }

    // MARK: Aufbau

    private func baueAuf() {
        fenster.title = "Zuordnen"
        fenster.delegate = self

        let frage = NSTextField(labelWithString: "„\(nennung)\" gehört zu welchem Eintrag?")
        frage.font = .systemFont(ofSize: 13, weight: .semibold)
        frage.lineBreakMode = .byTruncatingTail

        let erklaerung = NSTextField(wrappingLabelWithString:
            "Die Nennung wird eine weitere Schreibweise des gewählten Eintrags und bekommt "
            + "dessen Decknamen mit einem Buchstaben dahinter. Ein eigener Eintrag entsteht nicht.")
        erklaerung.font = .systemFont(ofSize: 11)
        erklaerung.textColor = .secondaryLabelColor

        suchfeld.placeholderString = "Suchen — Name, Deckname oder Typ"
        suchfeld.delegate = self
        suchfeld.sendsWholeSearchString = false
        suchfeld.sendsSearchStringImmediately = true

        let spalte = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("eintrag"))
        spalte.resizingMask = .autoresizingMask
        tabelle.addTableColumn(spalte)
        tabelle.headerView = nil
        tabelle.rowHeight = 38
        tabelle.style = .inset
        tabelle.dataSource = self
        tabelle.delegate = self
        tabelle.allowsEmptySelection = true
        tabelle.allowsMultipleSelection = false
        tabelle.target = self
        tabelle.doubleAction = #selector(zuordnen)
        tabelle.floatsGroupRows = true

        let rollflaeche = NSScrollView()
        rollflaeche.documentView = tabelle
        rollflaeche.hasVerticalScroller = true
        rollflaeche.borderType = .bezelBorder
        rollflaeche.translatesAutoresizingMaskIntoConstraints = false

        zaehler.font = .systemFont(ofSize: 11)
        zaehler.textColor = .secondaryLabelColor

        zuordnenKnopf.target = self
        zuordnenKnopf.action = #selector(zuordnen)
        zuordnenKnopf.bezelStyle = .rounded
        zuordnenKnopf.keyEquivalent = "\r"

        let abbrechen = NSButton(title: "Abbrechen", target: self, action: #selector(abbrechen))
        abbrechen.bezelStyle = .rounded
        abbrechen.keyEquivalent = "\u{1b}"

        let knopfleiste = NSStackView(views: [zaehler, NSView(), abbrechen, zuordnenKnopf])
        knopfleiste.orientation = .horizontal
        knopfleiste.spacing = 8

        let stapel = NSStackView(views: [frage, erklaerung, suchfeld, rollflaeche, knopfleiste])
        stapel.orientation = .vertical
        stapel.spacing = 10
        stapel.alignment = .leading
        stapel.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        stapel.translatesAutoresizingMaskIntoConstraints = false

        for schmal in [frage, erklaerung, suchfeld, knopfleiste] {
            schmal.setContentHuggingPriority(.required, for: .vertical)
        }
        rollflaeche.setContentHuggingPriority(.defaultLow, for: .vertical)

        let inhalt = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 480))
        inhalt.addSubview(stapel)
        NSLayoutConstraint.activate([
            stapel.topAnchor.constraint(equalTo: inhalt.topAnchor),
            stapel.leadingAnchor.constraint(equalTo: inhalt.leadingAnchor),
            stapel.trailingAnchor.constraint(equalTo: inhalt.trailingAnchor),
            stapel.bottomAnchor.constraint(equalTo: inhalt.bottomAnchor),
            frage.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -36),
            erklaerung.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -36),
            suchfeld.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -36),
            knopfleiste.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -36),
            rollflaeche.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -36),
            // Ohne festes Maß fällt die Rollfläche im verschachtelten Stapel
            // auf null zusammen und die Liste ist unsichtbar.
            rollflaeche.heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
        ])
        fenster.contentView = inhalt
    }

    // MARK: Ablauf

    /// Zeigt das Fenster modal und liefert die Wahl.
    func frageAb() -> Eintrag? {
        fenster.center()
        NSApp.activate(ignoringOtherApps: true)
        fenster.makeFirstResponder(suchfeld)
        let ausgang = NSApp.runModal(for: fenster)
        fenster.orderOut(nil)
        return ausgang == .OK ? gewaehlt : nil
    }

    @objc private func zuordnen() {
        guard let treffer = markierterEintrag else { NSSound.beep(); return }
        gewaehlt = treffer
        NSApp.stopModal(withCode: .OK)
    }

    @objc private func abbrechen() {
        gewaehlt = nil
        NSApp.stopModal(withCode: .cancel)
    }

    /// Ohne das liefe die Modalschleife nach einem Klick auf das rote
    /// Schließkreuz weiter und die App nähme keine Tasten mehr an.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        abbrechen()
        return false
    }

    // MARK: Inhalt

    /// Baut die Zeilen neu auf. Ausgelagert, damit die Prüfung die Gruppierung
    /// sehen kann, ohne ein Fenster zu öffnen.
    func fuelle(suche: String) {
        let gruppen = Eintragsliste.gruppiert(alle, suche: suche)
        zeilen = gruppen.flatMap { gruppe -> [Zeile] in
            [.kopf(gruppe.kategorie, gruppe.eintraege.count)] + gruppe.eintraege.map(Zeile.eintrag)
        }
        let anzahl = zeilen.filter { if case .eintrag = $0 { return true } else { return false } }.count
        zaehler.stringValue = anzahl == alle.count
            ? "\(anzahl) Einträge"
            : "\(anzahl) von \(alle.count)"
        tabelle.reloadData()
        // Nach dem Filtern soll die erste Trefferzeile schon stehen, damit ⏎
        // sofort zuordnet, ohne den Umweg über die Pfeiltasten.
        if let erste = zeilen.firstIndex(where: { if case .eintrag = $0 { return true } else { return false } }) {
            tabelle.selectRowIndexes([erste], byExtendingSelection: false)
            tabelle.scrollRowToVisible(erste)
        }
        zuordnenKnopf.isEnabled = anzahl > 0
    }

    private func waehleVorschlag() {
        guard let vorschlag,
              let index = zeilen.firstIndex(where: {
                  if case .eintrag(let eintrag) = $0 { return eintrag.id == vorschlag }
                  return false
              })
        else { return }
        tabelle.selectRowIndexes([index], byExtendingSelection: false)
        tabelle.scrollRowToVisible(index)
    }

    /// Der gerade markierte Eintrag, oder `nil` bei Kopfzeile und Leerauswahl.
    var markierterEintrag: Eintrag? {
        guard zeilen.indices.contains(tabelle.selectedRow),
              case .eintrag(let treffer) = zeilen[tabelle.selectedRow]
        else { return nil }
        return treffer
    }

    // MARK: Suchfeld

    func controlTextDidChange(_ meldung: Notification) {
        fuelle(suche: suchfeld.stringValue)
    }

    /// Pfeil runter im Suchfeld springt in die Liste. Sonst müsste man zum
    /// Blättern erst klicken oder tabben.
    func control(_ steuerung: NSControl, textView: NSTextView, doCommandBy befehl: Selector) -> Bool {
        switch befehl {
        case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.moveUp(_:)):
            fenster.makeFirstResponder(tabelle)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            zuordnen()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            abbrechen()
            return true
        default:
            return false
        }
    }

    // MARK: Tabelle

    func numberOfRows(in tableView: NSTableView) -> Int { zeilen.count }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        guard zeilen.indices.contains(row) else { return false }
        if case .kopf = zeilen[row] { return true }
        return false
    }

    /// Kopfzeilen lassen sich nicht anwählen — die Pfeiltasten überspringen
    /// sie dadurch von selbst.
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard zeilen.indices.contains(row) else { return false }
        if case .kopf = zeilen[row] { return false }
        return true
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard zeilen.indices.contains(row) else { return 38 }
        if case .kopf = zeilen[row] { return 24 }
        return 38
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard zeilen.indices.contains(row) else { return nil }
        switch zeilen[row] {
        case .kopf(let kategorie, let anzahl):
            return kopfzelle(kategorie, anzahl)
        case .eintrag(let eintrag):
            return eintragszelle(eintrag)
        }
    }

    private func kopfzelle(_ kategorie: Kategorie, _ anzahl: Int) -> NSView {
        let titel = NSTextField(labelWithString: "\(kategorie.anzeigename)  ·  \(anzahl)")
        titel.font = .systemFont(ofSize: 11, weight: .semibold)
        titel.textColor = .secondaryLabelColor
        titel.translatesAutoresizingMaskIntoConstraints = false

        let zelle = NSTableCellView()
        zelle.addSubview(titel)
        NSLayoutConstraint.activate([
            titel.leadingAnchor.constraint(equalTo: zelle.leadingAnchor, constant: 4),
            titel.centerYAnchor.constraint(equalTo: zelle.centerYAnchor),
        ])
        return zelle
    }

    private func eintragszelle(_ eintrag: Eintrag) -> NSView {
        let name = NSTextField(labelWithString: eintrag.text)
        name.font = .systemFont(ofSize: 12, weight: .medium)
        name.lineBreakMode = .byTruncatingTail

        var unten = eintrag.platzhalter
        if !eintrag.aliase.isEmpty {
            unten += "  ·  auch: " + eintrag.aliase.map(\.text).joined(separator: ", ")
        }
        let zusatz = NSTextField(labelWithString: unten)
        zusatz.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        zusatz.textColor = .secondaryLabelColor
        zusatz.lineBreakMode = .byTruncatingTail

        let texte = NSStackView(views: [name, zusatz])
        texte.orientation = .vertical
        texte.spacing = 1
        texte.alignment = .leading
        texte.translatesAutoresizingMaskIntoConstraints = false

        let zelle = NSTableCellView()
        zelle.addSubview(texte)
        NSLayoutConstraint.activate([
            texte.leadingAnchor.constraint(equalTo: zelle.leadingAnchor, constant: 6),
            texte.trailingAnchor.constraint(equalTo: zelle.trailingAnchor, constant: -6),
            texte.centerYAnchor.constraint(equalTo: zelle.centerYAnchor),
        ])
        return zelle
    }
}
