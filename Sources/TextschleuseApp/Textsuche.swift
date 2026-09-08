import AppKit

/// Die Suchzeile über dem Text. ⌘F klappt sie auf.
///
/// Gesucht wird in dem, was dasteht, samt eingesetzter Platzhalter — nicht im
/// Originaltext. Du suchst, was du siehst.
///
/// Die Treffer werden nicht dauerhaft eingefärbt. Das würde die Farben der
/// Chips überschreiben, und die tragen die wichtigere Information: grün heißt
/// steht fest, rot heißt geraten. Stattdessen wird der aktuelle Treffer
/// markiert und mit der gewohnten gelben Lupe kurz aufblitzen gelassen.
final class Textsuche: NSView {

    /// Läuft, wenn die Suche zugeklappt wird. Das Popup holt sich damit den
    /// Tastaturfokus zurück.
    var beimSchliessen: (() -> Void)?

    private weak var ziel: ChiptextAnsicht?
    private let feld = NSSearchField()
    private let zaehler = NSTextField(labelWithString: "")
    private var treffer: [NSRange] = []
    private var index = 0

    var istOffen: Bool { !isHidden }

    init(ziel: ChiptextAnsicht) {
        self.ziel = ziel
        super.init(frame: .zero)
        baueAuf()
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }

    private func baueAuf() {
        feld.placeholderString = "Im Text suchen"
        feld.font = .systemFont(ofSize: 12)
        feld.delegate = self
        feld.sendsWholeSearchString = false
        feld.sendsSearchStringImmediately = true
        feld.translatesAutoresizingMaskIntoConstraints = false

        zaehler.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        zaehler.textColor = .secondaryLabelColor

        let zurueck = NSButton(title: "‹", target: self, action: #selector(vorheriger))
        let vor = NSButton(title: "›", target: self, action: #selector(naechster))
        let zu = NSButton(title: "Fertig", target: self, action: #selector(schliesseGeklickt))
        for knopf in [zurueck, vor, zu] {
            knopf.bezelStyle = .rounded
            knopf.controlSize = .small
        }
        zurueck.toolTip = "Vorheriger Treffer (⌘⇧G)"
        vor.toolTip = "Nächster Treffer (⌘G oder ⏎)"

        let zeile = NSStackView(views: [feld, zaehler, zurueck, vor, zu])
        zeile.orientation = .horizontal
        zeile.spacing = 6
        zeile.translatesAutoresizingMaskIntoConstraints = false
        addSubview(zeile)

        NSLayoutConstraint.activate([
            zeile.topAnchor.constraint(equalTo: topAnchor),
            zeile.bottomAnchor.constraint(equalTo: bottomAnchor),
            zeile.leadingAnchor.constraint(equalTo: leadingAnchor),
            zeile.trailingAnchor.constraint(equalTo: trailingAnchor),
            feld.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
        ])
    }

    // MARK: Auf und zu

    func oeffne() {
        isHidden = false
        window?.makeFirstResponder(feld)
        feld.currentEditor()?.selectAll(nil)
        sucheNeu()
    }

    func schliesse() {
        isHidden = true
        treffer = []
        beimSchliessen?()
    }

    @objc private func schliesseGeklickt() { schliesse() }

    /// Nach jedem Neuaufbau des Textes aufrufen: die Fundstellen sind dann
    /// verschoben, die alten Bereiche zeigen ins Leere.
    func aktualisiere() {
        guard istOffen else { return }
        sucheNeu(springen: false)
    }

    // MARK: Suchen

    private func sucheNeu(springen: Bool = true) {
        treffer = []
        index = 0

        let begriff = feld.stringValue
        if let text = ziel?.string as NSString?, !begriff.isEmpty {
            var start = 0
            while start < text.length {
                let rest = NSRange(location: start, length: text.length - start)
                let gefunden = text.range(
                    of: begriff,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: rest
                )
                guard gefunden.location != NSNotFound else { break }
                treffer.append(gefunden)
                start = gefunden.location + max(1, gefunden.length)
            }
        }

        beschrifteZaehler()
        if springen, !treffer.isEmpty { springeZuAktuellem() }
    }

    private func beschrifteZaehler() {
        if feld.stringValue.isEmpty {
            zaehler.stringValue = ""
        } else if treffer.isEmpty {
            zaehler.stringValue = "nichts gefunden"
            zaehler.textColor = .systemRed
        } else {
            zaehler.stringValue = "\(index + 1) von \(treffer.count)"
            zaehler.textColor = .secondaryLabelColor
        }
    }

    private func springeZuAktuellem() {
        guard treffer.indices.contains(index), let ziel else { return }
        let bereich = treffer[index]
        ziel.setSelectedRange(bereich)
        ziel.scrollRangeToVisible(bereich)
        ziel.showFindIndicator(for: bereich)
        beschrifteZaehler()
    }

    /// Sucht ohne Tastatur. Für den Selbsttest, der keinen Bildschirm hat.
    @discardableResult
    func suche(nach begriff: String) -> Int {
        feld.stringValue = begriff
        sucheNeu()
        return treffer.count
    }

    @objc func naechster() {
        guard !treffer.isEmpty else { return }
        index = (index + 1) % treffer.count
        springeZuAktuellem()
    }

    @objc func vorheriger() {
        guard !treffer.isEmpty else { return }
        index = (index - 1 + treffer.count) % treffer.count
        springeZuAktuellem()
    }
}

extension Textsuche: NSSearchFieldDelegate {

    func controlTextDidChange(_ meldung: Notification) {
        sucheNeu()
    }

    func control(
        _ steuerelement: NSControl,
        textView: NSTextView,
        doCommandBy befehl: Selector
    ) -> Bool {
        switch befehl {
        case #selector(NSResponder.cancelOperation(_:)):
            schliesse()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            naechster()
            return true
        case #selector(NSResponder.moveDown(_:)):
            naechster()
            return true
        case #selector(NSResponder.moveUp(_:)):
            vorheriger()
            return true
        default:
            return false
        }
    }
}
