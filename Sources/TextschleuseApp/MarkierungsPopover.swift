import AppKit
import TextschleuseCore

/// Das kleine Feld, das bei einer Textmarkierung neben der Stelle aufgeht.
///
/// Es zeigt genau die Entscheidungen, die an dieser Stelle offenstehen:
/// welcher Typ, oder gehört das zu jemandem, den das Wörterbuch schon kennt.
/// Die Ziffern stehen mit dran, damit man sie beim Klicken mitlernt.
final class MarkierungsPopover: NSViewController {

    enum Entscheidung {
        case kategorie(Kategorie, merken: Bool)
        /// Ein selbst getippter Typ, so wie er im Feld stand.
        case eigenerTyp(String, merken: Bool)
        case gehoertZu
    }

    private let begriff: String
    /// Die Kategorien in der Reihenfolge der Ziffern — dieselben wie in der
    /// Leiste unten, samt zugeschalteten Erkennungen.
    private let kategorien: [Kategorie]
    private let kannZuordnen: Bool
    private let entscheidung: (Entscheidung) -> Void
    private let merkenHaken = NSButton(checkboxWithTitle: "dauerhaft merken", target: nil, action: nil)
    private let typFeld = NSTextField()
    /// Die Ziffernknöpfe. Ihre Tasten schlafen, solange im Typ-Feld getippt
    /// wird — sonst schnappt „1" beim Tippen von „Projekt1" den Knopf.
    private var ziffernKnoepfe: [NSButton] = []

    private let popover = NSPopover()

    init(
        begriff: String,
        kategorien: [Kategorie],
        kannZuordnen: Bool,
        entscheidung: @escaping (Entscheidung) -> Void
    ) {
        self.begriff = begriff
        self.kategorien = kategorien
        self.kannZuordnen = kannZuordnen
        self.entscheidung = entscheidung
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }

    override func loadView() {
        let kopf = NSTextField(labelWithString: kurz(begriff) + " schützen als")
        kopf.font = .systemFont(ofSize: 12, weight: .semibold)
        kopf.lineBreakMode = .byTruncatingMiddle

        // Umbrechend: mit allen zugeschalteten Erkennungen sind es zehn
        // Knöpfe, und die passen nicht in eine Zeile neben dem Text.
        let reihe = Fliessleiste()
        reihe.translatesAutoresizingMaskIntoConstraints = false
        reihe.setze(kategorien.enumerated().map { platz, kategorie in
            let taste = Kategorie.taste(fuerPlatz: platz)
            let knopf = Knoepfe.knopf(
                kategorie.anzeigename,
                symbol: Knoepfe.tastenkappe(taste),
                ziel: self,
                aktion: #selector(kategorieGewaehlt(_:)),
                hilfe: taste.map { "Taste \($0)" } ?? "Als \(kategorie.anzeigename) schützen"
            )
            knopf.tag = platz
            // Die Ziffer wirkt auch, während dieses Feld vorn ist.
            if let taste {
                knopf.keyEquivalent = taste
                knopf.keyEquivalentModifierMask = []
                ziffernKnoepfe.append(knopf)
            }
            return knopf
        })
        let breite: CGFloat = 500
        reihe.widthAnchor.constraint(equalToConstant: breite).isActive = true
        reihe.bemesse(breite: breite)

        let zuordnen = Knoepfe.knopf(
            "Gehört zu einem bekannten Eintrag …", symbol: "d.square",
            ziel: self, aktion: #selector(zuordnenGewaehlt),
            hilfe: "Taste D"
        )
        zuordnen.keyEquivalent = "d"
        zuordnen.keyEquivalentModifierMask = []
        zuordnen.isEnabled = kannZuordnen
        zuordnen.toolTip = kannZuordnen
            ? "Für den Fall, dass dieselbe Person im Text anders dasteht"
            : "Dafür muss erst ein Eintrag im Wörterbuch stehen"

        merkenHaken.state = .on
        merkenHaken.font = .systemFont(ofSize: 11)
        merkenHaken.toolTip = "Aus heißt: gilt nur für diesen Text."

        // Ein eigener Typ: „Projekt" ⏎ macht PROJEKT_… daraus.
        typFeld.placeholderString = "eigener Typ, z. B. Projekt — dann ⏎"
        typFeld.font = .systemFont(ofSize: 12)
        typFeld.target = self
        typFeld.action = #selector(typGewaehlt)
        typFeld.delegate = self
        typFeld.toolTip = "Steht vorn am Decknamen statt des Kürzels. Taste T fragt danach."
        let typEtikett = NSTextField(labelWithString: "Eigener Typ")
        typEtikett.font = .systemFont(ofSize: 11)
        typEtikett.textColor = .secondaryLabelColor
        let typZeile = NSStackView(views: [typEtikett, typFeld])
        typZeile.orientation = .horizontal
        typZeile.spacing = 6
        typFeld.widthAnchor.constraint(equalToConstant: 260).isActive = true

        let fuss = NSTextField(labelWithString: "⎋ schließt dieses Feld.")
        fuss.font = .systemFont(ofSize: 10)
        fuss.textColor = .tertiaryLabelColor

        let stapel = NSStackView(views: [kopf, reihe, typZeile, zuordnen, merkenHaken, fuss])
        stapel.orientation = .vertical
        stapel.spacing = 8
        stapel.alignment = .leading
        stapel.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 12, right: 14)
        view = stapel
    }

    private func kurz(_ text: String) -> String {
        let eineZeile = text.replacingOccurrences(of: "\n", with: " ")
        let gekuerzt = eineZeile.count > 40 ? String(eineZeile.prefix(40)) + " …" : eineZeile
        return "„\(gekuerzt)\""
    }

    // MARK: Auf und zu

    /// Zeigt das Feld an der Stelle im Text. `bereich` ist der Rahmen der
    /// Markierung in den Koordinaten von `neben`.
    func zeige(neben ansicht: NSView, bei bereich: NSRect) {
        popover.contentViewController = self
        popover.behavior = .transient
        popover.animates = false
        popover.show(relativeTo: bereich, of: ansicht, preferredEdge: .maxY)
    }

    func schliesse() {
        popover.performClose(nil)
    }

    var istOffen: Bool { popover.isShown }

    // MARK: Aktionen

    @objc private func kategorieGewaehlt(_ absender: NSButton) {
        guard kategorien.indices.contains(absender.tag) else { return }
        let merken = merkenHaken.state == .on
        schliesse()
        entscheidung(.kategorie(kategorien[absender.tag], merken: merken))
    }

    @objc private func zuordnenGewaehlt() {
        schliesse()
        entscheidung(.gehoertZu)
    }

    @objc private func typGewaehlt() {
        let eingabe = typFeld.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !eingabe.isEmpty else { return }
        let merken = merkenHaken.state == .on
        schliesse()
        entscheidung(.eigenerTyp(eingabe, merken: merken))
    }

    /// Für den Selbsttest: ist das Feld da?
    var hatTypFeld: Bool { typFeld.superview != nil }
}

extension MarkierungsPopover: NSTextFieldDelegate {

    func controlTextDidBeginEditing(_ meldung: Notification) {
        for knopf in ziffernKnoepfe { knopf.keyEquivalent = "" }
    }

    func controlTextDidEndEditing(_ meldung: Notification) {
        for knopf in ziffernKnoepfe {
            knopf.keyEquivalent = Kategorie.taste(fuerPlatz: knopf.tag) ?? ""
        }
    }
}
