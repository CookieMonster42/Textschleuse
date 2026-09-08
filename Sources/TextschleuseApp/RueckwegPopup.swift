import AppKit
import TextschleuseCore

/// Das Fenster für den Rückweg. Gleicher Aufbau wie beim Schützen: links der
/// Text, rechts die Liste. Nur andersherum — grün heißt auflösbar, rot heißt,
/// das Wörterbuch kennt den Platzhalter nicht.
final class RueckwegPopup: TastaturPanel {

    enum Ausgang {
        case uebernommen(String)
        case abgebrochen
    }

    private var ergebnis: RueckwegErgebnis
    private let woerterbuch: Woerterbuch
    private let unbekannte: [String: String]
    private let abschluss: (Ausgang) -> Void

    private var auswahl = 0
    private var bereiche: [UUID: NSRange] = [:]

    private let kopfzeile = NSTextField(labelWithString: "")
    private let warnzeile = NSTextField(labelWithString: "")
    private let flaeche = Textflaeche.bauen()
    private var textAnsicht: ChiptextAnsicht { flaeche.text }
    private var rollflaeche: NSScrollView { flaeche.rolle }
    private let liste = Fundstellenliste()
    private let knopfleiste = NSStackView()
    private let fusszeile = NSTextField(labelWithString: "")
    private let meldung = NSTextField(labelWithString: "")

    init(
        ergebnis: RueckwegErgebnis,
        woerterbuch: Woerterbuch = Woerterbuch(),
        unbekannte: [String: String] = [:],
        abschluss: @escaping (Ausgang) -> Void
    ) {
        self.ergebnis = ergebnis
        self.woerterbuch = woerterbuch
        self.unbekannte = unbekannte
        self.abschluss = abschluss

        let bildschirm = TastaturPanel.bildschirmUnterMaus
        let maximal = TastaturPanel.maximaleGroesse(auf: bildschirm)
        super.init(groesse: NSSize(width: min(1000, maximal.width), height: min(640, maximal.height)))

        baueOberflaeche()
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
        fusszeile.stringValue = "⏎ Kopieren · ⎋ Abbrechen · ↑ ↓ Platzhalter · ⌘N Neuer Text"

        let mitte = NSStackView(views: [rollflaeche, liste])
        mitte.orientation = .horizontal
        mitte.spacing = 12
        mitte.distribution = .fill
        mitte.translatesAutoresizingMaskIntoConstraints = false

        let stapel = NSStackView(views: [kopfzeile, warnzeile, mitte, knopfleiste, fusszeile])
        stapel.orientation = .vertical
        stapel.spacing = 10
        stapel.alignment = .leading
        stapel.edgeInsets = NSEdgeInsets(top: 28, left: 18, bottom: 16, right: 18)
        contentView = stapel

        for zeile in [kopfzeile, warnzeile, fusszeile] {
            zeile.setContentHuggingPriority(.required, for: .vertical)
        }
        knopfleiste.setContentHuggingPriority(.required, for: .vertical)
        mitte.setContentHuggingPriority(.defaultLow, for: .vertical)
        mitte.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        NSLayoutConstraint.activate([
            mitte.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -36),
            mitte.heightAnchor.constraint(greaterThanOrEqualToConstant: 260),
            liste.widthAnchor.constraint(equalToConstant: 260),
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
    private func verarbeite(_ ereignis: NSEvent) -> Bool {
        let zusatz = ereignis.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if zusatz.contains(.command) {
            if ereignis.charactersIgnoringModifiers?.lowercased() == "n" {
                neuEinlesen()
                return true
            }
            return false
        }

        switch ereignis.keyCode {
        case 36, 76:
            abschluss(.uebernommen(ergebnis.ergebnis))
            schliesseUndGibFokusZurueck()
            return true
        case 53:
            abschluss(.abgebrochen)
            schliesseUndGibFokusZurueck()
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

    override func keyDown(with ereignis: NSEvent) {
        if verarbeite(ereignis) { return }
        super.keyDown(with: ereignis)
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
