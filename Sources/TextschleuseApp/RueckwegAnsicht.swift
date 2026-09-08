import AppKit
import TextschleuseCore

/// Die Arbeitsfläche für den Rückweg. Gleicher Aufbau wie beim Schützen:
/// links der Text, rechts die Liste. Nur andersherum — grün heißt auflösbar,
/// rot heißt, das Wörterbuch kennt den Platzhalter nicht.
final class RueckwegAnsicht: NSView {

    var beiUebernahme: ((String) -> Void)?
    var beiAbbruch: (() -> Void)?

    private(set) var ergebnis: RueckwegErgebnis
    private let woerterbuch: Woerterbuch
    private let unbekannte: [String: String]

    private var auswahl = 0
    private var bereiche: [UUID: NSRange] = [:]

    private let kopfzeile = NSTextField(labelWithString: "")
    private let warnzeile = NSTextField(labelWithString: "")
    private let flaeche = Textflaeche.bauen()
    private var textAnsicht: ChiptextAnsicht { flaeche.text }
    private var rollflaeche: NSScrollView { flaeche.rolle }
    private let liste = Fundstellenliste()
    private lazy var suche = Textsuche(ziel: textAnsicht)
    private let knopfleiste = NSStackView()
    private let fusszeile = NSTextField(labelWithString: "")
    private let meldung = NSTextField(labelWithString: "")

    init(
        ergebnis: RueckwegErgebnis,
        woerterbuch: Woerterbuch = Woerterbuch(),
        unbekannte: [String: String] = [:]
    ) {
        self.ergebnis = ergebnis
        self.woerterbuch = woerterbuch
        self.unbekannte = unbekannte
        super.init(frame: NSRect(x: 0, y: 0, width: 960, height: 600))
        baueOberflaeche()
        aktualisiere()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }

    func setze(ergebnis neues: RueckwegErgebnis) {
        ergebnis = neues
        auswahl = 0
        meldung.isHidden = true
        aktualisiere()
    }

    // MARK: Aufbau

    private func baueOberflaeche() {
        kopfzeile.font = .systemFont(ofSize: 15, weight: .semibold)
        warnzeile.font = .systemFont(ofSize: 12)
        warnzeile.textColor = .secondaryLabelColor
        warnzeile.lineBreakMode = .byTruncatingTail

        textAnsicht.tastenweiche = { [weak self] ereignis in
            self?.verarbeite(ereignis) ?? false
        }

        liste.translatesAutoresizingMaskIntoConstraints = false
        liste.beiAuswahl = { [weak self] kennung in
            self?.waehleFund(kennung)
        }

        suche.translatesAutoresizingMaskIntoConstraints = false
        suche.beimSchliessen = { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.textAnsicht)
        }

        knopfleiste.orientation = .horizontal
        knopfleiste.spacing = 6
        let neu = NSButton(title: "Neuer Text (⌘N)", target: self, action: #selector(neuEinlesen))
        neu.toolTip = "Liest, was jetzt in der Zwischenablage liegt."
        neu.bezelStyle = .rounded
        neu.controlSize = .small
        knopfleiste.addArrangedSubview(neu)

        meldung.font = .systemFont(ofSize: 11)
        meldung.textColor = .systemRed
        meldung.isHidden = true
        knopfleiste.addArrangedSubview(meldung)

        fusszeile.font = .systemFont(ofSize: 11)
        fusszeile.textColor = .secondaryLabelColor
        fusszeile.stringValue = "⏎ Kopieren · ↑ ↓ Platzhalter · ⌘F Suchen · ⌘N Neuer Text · ⎋ Abbrechen"

        let mitte = NSStackView(views: [rollflaeche, liste])
        mitte.orientation = .horizontal
        mitte.spacing = 12
        mitte.distribution = .fill
        mitte.translatesAutoresizingMaskIntoConstraints = false

        let stapel = NSStackView(views: [kopfzeile, warnzeile, suche, mitte, knopfleiste, fusszeile])
        stapel.orientation = .vertical
        stapel.spacing = 10
        stapel.alignment = .leading
        stapel.edgeInsets = NSEdgeInsets(top: 28, left: 18, bottom: 16, right: 18)
        stapel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stapel)
        NSLayoutConstraint.activate([
            stapel.topAnchor.constraint(equalTo: topAnchor),
            stapel.leadingAnchor.constraint(equalTo: leadingAnchor),
            stapel.trailingAnchor.constraint(equalTo: trailingAnchor),
            stapel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        for zeile in [kopfzeile, warnzeile, fusszeile] {
            zeile.setContentHuggingPriority(.required, for: .vertical)
        }
        knopfleiste.setContentHuggingPriority(.required, for: .vertical)
        suche.setContentHuggingPriority(.required, for: .vertical)
        mitte.setContentHuggingPriority(.defaultLow, for: .vertical)
        mitte.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        NSLayoutConstraint.activate([
            mitte.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -36),
            mitte.heightAnchor.constraint(greaterThanOrEqualToConstant: 260),
            liste.widthAnchor.constraint(equalToConstant: 260),
            suche.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -36),
        ])
    }

    // MARK: Darstellung

    private func aktualisiere() {
        let sortiert = ergebnis.funde.sorted { $0.bereich.location < $1.bereich.location }
        auswahl = sortiert.isEmpty ? 0 : min(auswahl, sortiert.count - 1)
        let gewaehlt = sortiert.indices.contains(auswahl) ? sortiert[auswahl].id : nil

        let aufbau = aufbereiteterText(ausgewaehlt: gewaehlt)
        bereiche = aufbau.bereiche
        textAnsicht.textStorage?.setAttributedString(aufbau.text)

        beschrifteKopf()
        liste.zeige(
            sortiert.map(listenzeile),
            ausgewaehlt: gewaehlt,
            leertext: ergebnis.original.isEmpty
                ? "Kein Text zum Prüfen."
                : "Keine Platzhalter im Text.\n\nMit ⏎ kopierst du den Text unverändert."
        )

        if let gewaehlt, let bereich = bereiche[gewaehlt] {
            textAnsicht.scrollRangeToVisible(bereich)
        }
        suche.aktualisiere()
    }

    private func beschrifteKopf() {
        guard !ergebnis.original.isEmpty else {
            kopfzeile.stringValue = "In der Zwischenablage steht kein Text"
            warnzeile.stringValue = "Kopiere die KI-Antwort und drücke ⌘N."
            warnzeile.textColor = .secondaryLabelColor
            return
        }
        guard !ergebnis.funde.isEmpty else {
            kopfzeile.stringValue = "Keine Platzhalter gefunden"
            warnzeile.stringValue = "Der Text enthält nichts, was zurückzudrehen wäre."
            warnzeile.textColor = .secondaryLabelColor
            return
        }

        kopfzeile.stringValue = "\(ergebnis.aufgeloest.count) von \(ergebnis.funde.count) Platzhaltern aufgelöst"
        if ergebnis.offen.isEmpty {
            warnzeile.stringValue = "Alle Platzhalter sind bekannt."
            warnzeile.textColor = .secondaryLabelColor
        } else {
            let liste = Set(ergebnis.offen.map(\.normal)).sorted().joined(separator: ", ")
            warnzeile.stringValue = "Bleiben stehen, weil das Wörterbuch sie nicht kennt: \(liste)"
            warnzeile.textColor = .systemRed
        }
    }

    private func listenzeile(_ fund: PlatzhalterFund) -> Fundstellenliste.Zeile {
        Fundstellenliste.Zeile(
            id: fund.id,
            begriff: fund.klartext ?? fund.geschrieben,
            deckname: fund.normal,
            status: fund.istAufloesbar ? "wird eingesetzt" : "unbekannt, bleibt stehen",
            farbe: fund.istAufloesbar ? .systemGreen : .systemRed,
            abgeschwaecht: !fund.istAufloesbar
        )
    }

    /// Der zurückgedrehte Text mit den eingesetzten Namen hervorgehoben, damit
    /// du siehst, wo etwas passiert ist.
    private func aufbereiteterText(ausgewaehlt: UUID?) -> Chiptext.Ergebnis {
        let fertig = NSMutableAttributedString(
            string: ergebnis.ergebnis,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor,
            ]
        )

        // Von vorn durchgehen und die eingesetzten Stellen einfärben. Der
        // Versatz ergibt sich aus der Längendifferenz der schon ersetzten.
        var stellen: [UUID: NSRange] = [:]
        var versatz = 0
        for fund in ergebnis.funde.sorted(by: { $0.bereich.location < $1.bereich.location }) {
            let laenge = (fund.klartext ?? fund.geschrieben).count
            let bereich = NSRange(location: fund.bereich.location + versatz, length: laenge)
            versatz += laenge - fund.bereich.length
            guard bereich.location >= 0, NSMaxRange(bereich) <= fertig.length else { continue }

            let farbe: NSColor = fund.istAufloesbar ? .systemGreen : .systemRed
            fertig.addAttributes([
                .backgroundColor: farbe.withAlphaComponent(fund.id == ausgewaehlt ? 0.34 : 0.16),
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            ], range: bereich)
            if fund.id == ausgewaehlt {
                fertig.addAttributes([
                    .underlineStyle: NSUnderlineStyle.thick.rawValue,
                    .underlineColor: farbe,
                ], range: bereich)
            }
            stellen[fund.id] = bereich
        }
        return Chiptext.Ergebnis(text: fertig, bereiche: stellen)
    }

    // MARK: Tastatur

    @discardableResult
    func verarbeite(_ ereignis: NSEvent) -> Bool {
        let zusatz = ereignis.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if zusatz.contains(.command) {
            switch ereignis.charactersIgnoringModifiers?.lowercased() {
            case "n":
                neuEinlesen()
                return true
            case "f":
                suche.oeffne()
                return true
            case "g":
                if zusatz.contains(.shift) { suche.vorheriger() } else { suche.naechster() }
                return true
            default:
                return false
            }
        }

        switch ereignis.keyCode {
        case 36, 76:
            beiUebernahme?(ergebnis.ergebnis)
            return true
        case 53:
            beiAbbruch?()
            return true
        case 126:
            waehle(auswahl - 1)
            return true
        case 125:
            waehle(auswahl + 1)
            return true
        default:
            return false
        }
    }

    private func waehle(_ index: Int) {
        guard !ergebnis.funde.isEmpty else { return }
        auswahl = (index + ergebnis.funde.count) % ergebnis.funde.count
        aktualisiere()
    }

    private func waehleFund(_ kennung: UUID) {
        let sortiert = ergebnis.funde.sorted { $0.bereich.location < $1.bereich.location }
        guard let index = sortiert.firstIndex(where: { $0.id == kennung }) else { return }
        auswahl = index
        aktualisiere()
    }

    @objc private func neuEinlesen() {
        guard let text = Zwischenablage.lies() else {
            meldung.stringValue = "In der Zwischenablage steht kein Text."
            meldung.isHidden = false
            return
        }
        guard text != ergebnis.original else {
            meldung.stringValue = "In der Zwischenablage liegt derselbe Text wie hier."
            meldung.isHidden = false
            return
        }

        ergebnis = Rueckweg.analysiere(text, woerterbuch: woerterbuch, unbekannte: unbekannte)
        auswahl = 0
        meldung.isHidden = true
        aktualisiere()
    }
}
