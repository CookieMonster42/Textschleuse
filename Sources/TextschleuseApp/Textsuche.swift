import AppKit
import TextschleuseCore

/// Die Suchzeile über dem Text. ⌘F klappt sie auf.
///
/// Gesucht wird in dem, was dasteht, samt eingesetzter Platzhalter — nicht im
/// Originaltext. Du suchst, was du siehst.
///
/// Die Treffer werden nicht dauerhaft eingefärbt. Das würde die Farben der
/// Chips überschreiben, und die tragen die wichtigere Information: grün heißt
/// steht fest, rot heißt geraten. Stattdessen wird der aktuelle Treffer
/// markiert und mit der gewohnten gelben Lupe kurz aufblitzen gelassen.
///
/// Darunter, wo es etwas zu ersetzen gibt, eine zweite Zeile: der Ersatz, ein
/// Haken für ganze Wörter, „Ersetzen" und „Alle ersetzen". Ersetzt wird im
/// Originaltext; das macht der Besitzer der Zeile über `beimErsetzen`. Im
/// Rückweg bleibt die Zeile verborgen — dort gibt es nichts zu ersetzen, und
/// eine Zeile ohne Wirkung wäre eine Falle.
final class Textsuche: NSView {

    /// Was ersetzt werden soll. `nurAktuellen` ist der Treffer in der
    /// Anzeige, auf den es geht; nil heißt alle.
    struct Auftrag {
        var begriff: String
        var ersatz: String
        var wortgrenzen: Bool
        var nurAktuellen: NSRange?
    }

    /// Läuft, wenn die Suche zugeklappt wird. Das Popup holt sich damit den
    /// Tastaturfokus zurück.
    var beimSchliessen: (() -> Void)?
    /// Führt den Ersatz aus und liefert, wie viele Stellen es waren.
    var beimErsetzen: ((Auftrag) -> Int)?

    private weak var ziel: ChiptextAnsicht?
    private let feld = NSSearchField()
    private let zaehler = NSTextField(labelWithString: "")
    private let ersatzFeld = NSTextField()
    private let wortgrenzenHaken = NSButton(checkboxWithTitle: "Ganze Wörter", target: nil, action: nil)
    private var ersetzenKnopf = NSButton()
    private var alleKnopf = NSButton()
    private let ersatzZeile = NSStackView()
    private var treffer: [NSRange] = []
    private var index = 0
    private let mitErsetzen: Bool

    var istOffen: Bool { !isHidden }

    init(ziel: ChiptextAnsicht, mitErsetzen: Bool = false) {
        self.ziel = ziel
        self.mitErsetzen = mitErsetzen
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

        ersatzFeld.placeholderString = "Ersetzen durch"
        ersatzFeld.font = .systemFont(ofSize: 12)
        ersatzFeld.delegate = self
        ersatzFeld.translatesAutoresizingMaskIntoConstraints = false
        ersatzFeld.toolTip = "⏎ ersetzt den aktuellen Treffer"
        wortgrenzenHaken.controlSize = .small
        wortgrenzenHaken.font = .systemFont(ofSize: 11)
        wortgrenzenHaken.target = self
        wortgrenzenHaken.action = #selector(wortgrenzenGeaendert)
        wortgrenzenHaken.toolTip = "Nur ganze Wörter: „Mai\" trifft nicht „Maier\"."
        ersetzenKnopf = NSButton(title: "Ersetzen", target: self, action: #selector(ersetzeAktuellen))
        ersetzenKnopf.toolTip = "Den aktuellen Treffer ersetzen und zum nächsten gehen"
        alleKnopf = NSButton(title: "Alle ersetzen", target: self, action: #selector(ersetzeAlle))
        alleKnopf.toolTip = "Jede Stelle im Text ersetzen. ⌘Z nimmt alles auf einmal zurück."
        for knopf in [ersetzenKnopf, alleKnopf] {
            knopf.bezelStyle = .rounded
            knopf.controlSize = .small
        }

        ersatzZeile.setViews([ersatzFeld, wortgrenzenHaken, ersetzenKnopf, alleKnopf], in: .leading)
        ersatzZeile.orientation = .horizontal
        ersatzZeile.spacing = 6
        ersatzZeile.translatesAutoresizingMaskIntoConstraints = false
        ersatzZeile.isHidden = !mitErsetzen

        let stapel = NSStackView(views: [zeile, ersatzZeile])
        stapel.orientation = .vertical
        stapel.alignment = .leading
        stapel.spacing = 6
        stapel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stapel)

        NSLayoutConstraint.activate([
            stapel.topAnchor.constraint(equalTo: topAnchor),
            stapel.bottomAnchor.constraint(equalTo: bottomAnchor),
            stapel.leadingAnchor.constraint(equalTo: leadingAnchor),
            stapel.trailingAnchor.constraint(equalTo: trailingAnchor),
            feld.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            // Der Ersatz steht bündig unter dem Suchbegriff.
            ersatzFeld.widthAnchor.constraint(equalTo: feld.widthAnchor),
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
    /// verschoben, die alten Bereiche zeigen ins Leere. Die Stelle in der
    /// Trefferliste bleibt, damit „Ersetzen" beim nächsten Treffer landet
    /// und nicht wieder vorn.
    func aktualisiere() {
        guard istOffen else { return }
        let bisher = index
        sucheNeu(springen: false)
        index = treffer.isEmpty ? 0 : min(bisher, treffer.count - 1)
        beschrifteZaehler()
    }

    // MARK: Suchen

    private var wortgrenzen: Bool { wortgrenzenHaken.state == .on }

    private func sucheNeu(springen: Bool = true) {
        treffer = []
        index = 0

        let begriff = feld.stringValue
        if let text = ziel?.string, !begriff.isEmpty {
            treffer = Textersatz.vorkommen(von: begriff, in: text, wortgrenzen: wortgrenzen)
        }

        beschrifteZaehler()
        aktualisiereKnoepfe()
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

    private func aktualisiereKnoepfe() {
        let geht = !treffer.isEmpty && beimErsetzen != nil
        ersetzenKnopf.isEnabled = geht
        alleKnopf.isEnabled = geht
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

    // MARK: Ersetzen

    @objc private func wortgrenzenGeaendert() {
        sucheNeu(springen: false)
    }

    @objc private func ersetzeAktuellen() {
        guard treffer.indices.contains(index) else { return }
        let anzahl = beimErsetzen?(Auftrag(
            begriff: feld.stringValue,
            ersatz: ersatzFeld.stringValue,
            wortgrenzen: wortgrenzen,
            nurAktuellen: treffer[index]
        )) ?? 0
        // Der Besitzer baut den Text neu und ruft `aktualisiere`; danach
        // steht der Zeiger auf dem nächsten Treffer.
        if anzahl == 0 {
            zaehler.stringValue = "Treffer liegt in einem Decknamen"
            zaehler.textColor = .systemRed
        } else if !treffer.isEmpty {
            springeZuAktuellem()
        }
    }

    @objc private func ersetzeAlle() {
        guard !treffer.isEmpty else { return }
        let anzahl = beimErsetzen?(Auftrag(
            begriff: feld.stringValue,
            ersatz: ersatzFeld.stringValue,
            wortgrenzen: wortgrenzen,
            nurAktuellen: nil
        )) ?? 0
        zaehler.stringValue = anzahl == 1 ? "1 Stelle ersetzt" : "\(anzahl) Stellen ersetzt"
        zaehler.textColor = .secondaryLabelColor
    }

    /// Für den Selbsttest: Ersatz setzen und alle ersetzen, ohne Tastatur.
    @discardableResult
    func ersetzeAlleFuerPruefung(_ begriff: String, durch ersatz: String, wortgrenzen: Bool) -> Int {
        feld.stringValue = begriff
        ersatzFeld.stringValue = ersatz
        wortgrenzenHaken.state = wortgrenzen ? .on : .off
        sucheNeu(springen: false)
        guard !treffer.isEmpty else { return 0 }
        return beimErsetzen?(Auftrag(
            begriff: begriff, ersatz: ersatz, wortgrenzen: wortgrenzen, nurAktuellen: nil
        )) ?? 0
    }

    func ersetzeAktuellenFuerPruefung(_ begriff: String, durch ersatz: String) -> Int {
        feld.stringValue = begriff
        ersatzFeld.stringValue = ersatz
        sucheNeu(springen: false)
        guard treffer.indices.contains(index) else { return 0 }
        return beimErsetzen?(Auftrag(
            begriff: begriff, ersatz: ersatz, wortgrenzen: wortgrenzen, nurAktuellen: treffer[index]
        )) ?? 0
    }

    var hatErsatzzeile: Bool { !ersatzZeile.isHidden }
}

extension Textsuche: NSSearchFieldDelegate, NSTextFieldDelegate {

    func controlTextDidChange(_ meldung: Notification) {
        guard (meldung.object as AnyObject?) === feld else { return }
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
            if steuerelement === ersatzFeld { ersetzeAktuellen() } else { naechster() }
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
