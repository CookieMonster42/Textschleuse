import AppKit

/// Die Liste rechts im Popup. Eine Zeile je Fundstelle: Begriff, Deckname,
/// Status.
///
/// Sie beantwortet die Frage, die der Fließtext nicht beantwortet: was genau
/// wandert ins Wörterbuch, was gilt nur für diesen Text, und was ist noch
/// offen.
final class Fundstellenliste: NSView {

    struct Zeile {
        var id: UUID
        var begriff: String
        var deckname: String
        var status: String
        var farbe: NSColor
        var abgeschwaecht: Bool
    }

    /// Feuert, wenn du eine Zeile anklickst.
    var beiAuswahl: ((UUID) -> Void)?

    private let tabelle = NSTableView()
    private let rollflaeche = NSScrollView()
    private let ueberschrift = NSTextField(labelWithString: "Fundstellen")
    private let leerhinweis = NSTextField(wrappingLabelWithString: "")
    private var zeilen: [Zeile] = []
    /// Verhindert, dass ein programmgesteuertes Auswählen zurückmeldet und
    /// eine Schleife auslöst.
    private var stelltGeradeEin = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        baueAuf()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }

    private func baueAuf() {
        ueberschrift.font = .systemFont(ofSize: 11, weight: .semibold)
        ueberschrift.textColor = .secondaryLabelColor

        let spalte = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("fundstelle"))
        spalte.resizingMask = .autoresizingMask
        tabelle.addTableColumn(spalte)
        tabelle.headerView = nil
        tabelle.rowHeight = 42
        tabelle.style = .inset
        tabelle.backgroundColor = .clear
        tabelle.dataSource = self
        tabelle.delegate = self
        tabelle.allowsEmptySelection = true
        tabelle.allowsMultipleSelection = false
        // Die Liste darf den Fokus haben — dann navigieren Pfeil hoch und
        // runter von Natur aus zwischen den Fundstellen. Im Text täten sie
        // das nicht, dort bewegen sie die Schreibmarke.
        tabelle.refusesFirstResponder = false

        rollflaeche.documentView = tabelle
        rollflaeche.hasVerticalScroller = true
        rollflaeche.borderType = .noBorder
        rollflaeche.drawsBackground = true
        rollflaeche.backgroundColor = .textBackgroundColor
        rollflaeche.wantsLayer = true
        rollflaeche.layer?.cornerRadius = 8
        rollflaeche.translatesAutoresizingMaskIntoConstraints = false

        leerhinweis.font = .systemFont(ofSize: 11)
        leerhinweis.textColor = .tertiaryLabelColor
        leerhinweis.alignment = .center
        leerhinweis.translatesAutoresizingMaskIntoConstraints = false

        ueberschrift.translatesAutoresizingMaskIntoConstraints = false
        addSubview(ueberschrift)
        addSubview(rollflaeche)
        addSubview(leerhinweis)

        NSLayoutConstraint.activate([
            ueberschrift.topAnchor.constraint(equalTo: topAnchor),
            ueberschrift.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            rollflaeche.topAnchor.constraint(equalTo: ueberschrift.bottomAnchor, constant: 6),
            rollflaeche.leadingAnchor.constraint(equalTo: leadingAnchor),
            rollflaeche.trailingAnchor.constraint(equalTo: trailingAnchor),
            rollflaeche.bottomAnchor.constraint(equalTo: bottomAnchor),
            leerhinweis.centerYAnchor.constraint(equalTo: rollflaeche.centerYAnchor),
            leerhinweis.leadingAnchor.constraint(equalTo: rollflaeche.leadingAnchor, constant: 16),
            leerhinweis.trailingAnchor.constraint(equalTo: rollflaeche.trailingAnchor, constant: -16),
        ])
    }

    /// Setzt den Tastaturfokus in die Liste.
    @discardableResult
    func fokussiere() -> Bool {
        guard !zeilen.isEmpty else { return false }
        return window?.makeFirstResponder(tabelle) ?? false
    }

    var hatFokus: Bool { window?.firstResponder === tabelle }

    func zeige(_ neue: [Zeile], ausgewaehlt: UUID?, leertext: String) {
        zeilen = neue
        ueberschrift.stringValue = neue.isEmpty
            ? "Fundstellen"
            : "Fundstellen (\(neue.count))"
        leerhinweis.stringValue = leertext
        leerhinweis.isHidden = !neue.isEmpty
        tabelle.reloadData()

        stelltGeradeEin = true
        if let ausgewaehlt, let index = zeilen.firstIndex(where: { $0.id == ausgewaehlt }) {
            tabelle.selectRowIndexes([index], byExtendingSelection: false)
            tabelle.scrollRowToVisible(index)
        } else {
            tabelle.deselectAll(nil)
        }
        stelltGeradeEin = false
    }
}

extension Fundstellenliste: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { zeilen.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard zeilen.indices.contains(row) else { return nil }
        let zeile = zeilen[row]

        let punkt = NSView()
        punkt.wantsLayer = true
        punkt.layer?.backgroundColor = zeile.farbe.cgColor
        punkt.layer?.cornerRadius = 4
        punkt.translatesAutoresizingMaskIntoConstraints = false

        let begriff = NSTextField(labelWithString: zeile.begriff)
        begriff.font = .systemFont(ofSize: 12, weight: .medium)
        begriff.lineBreakMode = .byTruncatingTail
        begriff.textColor = zeile.abgeschwaecht ? .tertiaryLabelColor : .labelColor

        let unterzeile = NSTextField(labelWithString: "\(zeile.deckname) · \(zeile.status)")
        unterzeile.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        unterzeile.textColor = .secondaryLabelColor
        unterzeile.lineBreakMode = .byTruncatingTail

        let texte = NSStackView(views: [begriff, unterzeile])
        texte.orientation = .vertical
        texte.spacing = 1
        texte.alignment = .leading
        texte.translatesAutoresizingMaskIntoConstraints = false

        let zelle = NSTableCellView()
        zelle.addSubview(punkt)
        zelle.addSubview(texte)
        NSLayoutConstraint.activate([
            punkt.widthAnchor.constraint(equalToConstant: 8),
            punkt.heightAnchor.constraint(equalToConstant: 8),
            punkt.leadingAnchor.constraint(equalTo: zelle.leadingAnchor, constant: 4),
            punkt.centerYAnchor.constraint(equalTo: zelle.centerYAnchor),
            texte.leadingAnchor.constraint(equalTo: punkt.trailingAnchor, constant: 8),
            texte.trailingAnchor.constraint(equalTo: zelle.trailingAnchor, constant: -4),
            texte.centerYAnchor.constraint(equalTo: zelle.centerYAnchor),
        ])
        return zelle
    }

    /// Kein Tippen-zum-Springen. Sonst schluckt die Tabelle die Ziffern, mit
    /// denen die Kategorie zugewiesen wird.
    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        nil
    }

    func tableViewSelectionDidChange(_ meldung: Notification) {
        guard !stelltGeradeEin, zeilen.indices.contains(tabelle.selectedRow) else { return }
        beiAuswahl?(zeilen[tabelle.selectedRow].id)
    }
}
