import AppKit
import TextschleuseCore

/// Die Pflege der Freiliste: Wörter, die nie als Vermutung durchgehen.
///
/// Eingebaute Einträge stehen grau da und lassen sich nicht entfernen. Was du
/// selbst aufnimmst, kannst du auch wieder herunternehmen.
final class FreilisteAnsicht: NSView {

    /// Meldet ein geändertes Wörterbuch nach oben, damit es in die Datei kommt.
    var beimSichern: ((Woerterbuch) -> Void)?

    private var woerterbuch: Woerterbuch
    private let tabelle = NSTableView()
    private let eingabe = NSTextField()
    private let meldung = NSTextField(labelWithString: "")
    private var zeilen: [(wort: String, eingebaut: Bool)] = []

    init(woerterbuch: Woerterbuch) {
        self.woerterbuch = woerterbuch
        super.init(frame: NSRect(x: 0, y: 0, width: 520, height: 340))
        baueAuf()
        aktualisiere()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }

    func setze(woerterbuch neues: Woerterbuch) {
        woerterbuch = neues
        aktualisiere()
    }

    // MARK: Aufbau

    private func baueAuf() {
        let erklaerung = NSTextField(wrappingLabelWithString:
            "Diese Wörter werden nie als Vermutung vorgeschlagen. „August\" und „Mai\" sind "
            + "Monate und Vornamen zugleich; ohne die Liste musst du sie in jedem Text neu "
            + "verwerfen.\n\n"
            + "Die Liste bremst nur Vermutungen. In „geboren am 3. August 1979\" greift die "
            + "Datumsregel und das Datum bleibt geschützt. Ein Wort, das du ausdrücklich ins "
            + "Wörterbuch aufgenommen hast, wird ebenfalls weiter ersetzt.")
        erklaerung.font = .systemFont(ofSize: 11)
        erklaerung.textColor = .secondaryLabelColor
        erklaerung.preferredMaxLayoutWidth = 470

        let spalte = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("wort"))
        spalte.resizingMask = .autoresizingMask
        tabelle.addTableColumn(spalte)
        tabelle.headerView = nil
        tabelle.rowHeight = 22
        tabelle.style = .inset
        tabelle.dataSource = self
        tabelle.delegate = self

        let rollflaeche = NSScrollView()
        rollflaeche.documentView = tabelle
        rollflaeche.hasVerticalScroller = true
        rollflaeche.scrollerStyle = .legacy
        rollflaeche.autohidesScrollers = false
        rollflaeche.borderType = .bezelBorder
        rollflaeche.translatesAutoresizingMaskIntoConstraints = false

        eingabe.placeholderString = "Wort aufnehmen, dann ⏎"
        eingabe.target = self
        eingabe.action = #selector(aufnehmen)
        eingabe.translatesAutoresizingMaskIntoConstraints = false

        let hinzu = NSButton(title: "Aufnehmen", target: self, action: #selector(aufnehmen))
        let entfernen = NSButton(title: "Entfernen", target: self, action: #selector(entfernen))
        for knopf in [hinzu, entfernen] {
            knopf.bezelStyle = .rounded
            knopf.controlSize = .small
        }

        meldung.font = .systemFont(ofSize: 11)
        meldung.textColor = .secondaryLabelColor
        meldung.lineBreakMode = .byTruncatingTail

        let zeile = NSStackView(views: [eingabe, hinzu, entfernen])
        zeile.orientation = .horizontal
        zeile.spacing = 8
        zeile.translatesAutoresizingMaskIntoConstraints = false

        let stapel = NSStackView(views: [erklaerung, rollflaeche, zeile, meldung])
        stapel.orientation = .vertical
        stapel.spacing = 10
        stapel.alignment = .leading
        stapel.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stapel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stapel)

        rollflaeche.setContentHuggingPriority(.defaultLow, for: .vertical)
        for fest in [erklaerung, zeile, meldung] {
            fest.setContentHuggingPriority(.required, for: .vertical)
        }

        NSLayoutConstraint.activate([
            stapel.topAnchor.constraint(equalTo: topAnchor),
            stapel.leadingAnchor.constraint(equalTo: leadingAnchor),
            stapel.trailingAnchor.constraint(equalTo: trailingAnchor),
            stapel.bottomAnchor.constraint(equalTo: bottomAnchor),
            erklaerung.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -40),
            rollflaeche.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -40),
            zeile.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -40),
            meldung.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -40),
            // Ohne festes Maß fällt die Rollfläche im Stapel auf null zusammen.
            rollflaeche.heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
        ])
    }

    // MARK: Bedienung

    @objc func aufnehmen() {
        let wort = eingabe.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wort.isEmpty else { return }
        guard woerterbuch.gibFrei(wort) else {
            melde("„\(wort)\" steht schon auf der Liste.")
            return
        }
        eingabe.stringValue = ""
        melde("„\(wort)\" wird nicht mehr vorgeschlagen.")
        sichere()
    }

    @objc func entfernen() {
        guard zeilen.indices.contains(tabelle.selectedRow) else {
            melde("Wähle zuerst ein Wort aus.")
            return
        }
        let zeile = zeilen[tabelle.selectedRow]
        guard !zeile.eingebaut else {
            melde("„\(zeile.wort)\" ist eingebaut und bleibt auf der Liste.")
            return
        }
        woerterbuch.nimmVonFreiliste(zeile.wort)
        melde("„\(zeile.wort)\" wird wieder vorgeschlagen.")
        sichere()
    }

    /// Für den Selbsttest: nimmt ein Wort auf, ohne den Umweg über das Feld.
    func aufnehmenFuerPruefung(_ wort: String) {
        eingabe.stringValue = wort
        aufnehmen()
    }

    func waehleFuerPruefung(_ wort: String) {
        guard let index = zeilen.firstIndex(where: { Freiliste.gleich($0.wort, wort) }) else { return }
        tabelle.selectRowIndexes([index], byExtendingSelection: false)
    }

    func zeilenFuerPruefung() -> [(wort: String, eingebaut: Bool)] { zeilen }
    func meldungFuerPruefung() -> String { meldung.stringValue }
    func woerterbuchFuerPruefung() -> Woerterbuch { woerterbuch }

    private func sichere() {
        aktualisiere()
        beimSichern?(woerterbuch)
    }

    private func melde(_ text: String) {
        meldung.stringValue = text
    }

    private func aktualisiere() {
        zeilen = Freiliste.alle(eigene: woerterbuch.eigeneFreieWoerter)
        tabelle.reloadData()
    }
}

extension FreilisteAnsicht: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { zeilen.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard zeilen.indices.contains(row) else { return nil }
        let zeile = zeilen[row]
        let feld = NSTextField(labelWithString: zeile.eingebaut
            ? "\(zeile.wort)   (eingebaut)"
            : zeile.wort)
        feld.font = .systemFont(ofSize: 12)
        feld.textColor = zeile.eingebaut ? .secondaryLabelColor : .labelColor
        feld.lineBreakMode = .byTruncatingTail
        return feld
    }
}
