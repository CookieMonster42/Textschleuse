import AppKit
import TextschleuseCore

/// Das Fenster für den Rückweg. Gleiche Bedienung wie beim Schützen, nur
/// andersherum: grün heißt auflösbar, rot heißt unbekannt.
final class RueckwegPopup: TastaturPanel {

    enum Ausgang {
        case uebernommen(String)
        case abgebrochen
    }

    private let ergebnis: RueckwegErgebnis
    private let abschluss: (Ausgang) -> Void

    private let kopfzeile = NSTextField(labelWithString: "")
    private let warnzeile = NSTextField(labelWithString: "")
    private let flaeche = Textflaeche.bauen()
    private var textAnsicht: NSTextView { flaeche.text }
    private var rollflaeche: NSScrollView { flaeche.rolle }
    private let fusszeile = NSTextField(labelWithString: "⏎ Kopieren · ⎋ Abbrechen")

    init(ergebnis: RueckwegErgebnis, abschluss: @escaping (Ausgang) -> Void) {
        self.ergebnis = ergebnis
        self.abschluss = abschluss

        let bildschirm = TastaturPanel.bildschirmUnterMaus
        let maximal = TastaturPanel.maximaleGroesse(auf: bildschirm)
        super.init(groesse: NSSize(width: min(860, maximal.width), height: min(560, maximal.height)))

        baueOberflaeche()
    }

    private func baueOberflaeche() {
        kopfzeile.font = .systemFont(ofSize: 15, weight: .semibold)
        kopfzeile.stringValue = "\(ergebnis.aufgeloest.count) von \(ergebnis.funde.count) Platzhaltern aufgelöst"

        warnzeile.font = .systemFont(ofSize: 12)
        warnzeile.lineBreakMode = .byWordWrapping
        if ergebnis.offen.isEmpty {
            warnzeile.stringValue = "Alle Platzhalter sind bekannt."
            warnzeile.textColor = .secondaryLabelColor
        } else {
            let liste = Set(ergebnis.offen.map(\.normal)).sorted().joined(separator: ", ")
            warnzeile.stringValue = "Bleiben stehen, weil das Wörterbuch sie nicht kennt: \(liste)"
            warnzeile.textColor = .systemRed
        }

        textAnsicht.textStorage?.setAttributedString(aufbereiteterText())

        fusszeile.font = .systemFont(ofSize: 11)
        fusszeile.textColor = .secondaryLabelColor

        let stapel = NSStackView(views: [kopfzeile, warnzeile, rollflaeche, fusszeile])
        stapel.orientation = .vertical
        stapel.spacing = 10
        stapel.alignment = .leading
        stapel.edgeInsets = NSEdgeInsets(top: 28, left: 18, bottom: 16, right: 18)
        contentView = stapel

        for zeile in [kopfzeile, warnzeile, fusszeile] {
            zeile.setContentHuggingPriority(.required, for: .vertical)
        }
        rollflaeche.setContentHuggingPriority(.defaultLow, for: .vertical)
        rollflaeche.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        NSLayoutConstraint.activate([
            rollflaeche.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -36),
            rollflaeche.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])
    }

    /// Der zurückgedrehte Text mit den eingesetzten Namen hervorgehoben, damit
    /// du siehst, wo etwas passiert ist.
    private func aufbereiteterText() -> NSAttributedString {
        let fertig = NSMutableAttributedString(
            string: ergebnis.ergebnis,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor,
            ]
        )

        // Von hinten nach vorn durchgehen und die eingesetzten Stellen
        // einfärben. Die Verschiebung ergibt sich aus der Längendifferenz.
        let sortiert = ergebnis.funde.sorted { $0.bereich.location < $1.bereich.location }
        var versatz = 0
        for fund in sortiert {
            let laenge = fund.klartext?.count ?? fund.geschrieben.count
            let start = fund.bereich.location + versatz
            let bereich = NSRange(location: start, length: laenge)
            guard bereich.location >= 0, NSMaxRange(bereich) <= fertig.length else { continue }
            let farbe: NSColor = fund.istAufloesbar ? .systemGreen : .systemRed
            fertig.addAttributes([.backgroundColor: farbe.withAlphaComponent(0.18)], range: bereich)
            versatz += laenge - fund.bereich.length
        }
        return fertig
    }

    override func keyDown(with ereignis: NSEvent) {
        switch ereignis.keyCode {
        case 36, 76:
            abschluss(.uebernommen(ergebnis.ergebnis))
            schliesseUndGibFokusZurueck()
        case 53:
            abschluss(.abgebrochen)
            schliesseUndGibFokusZurueck()
        default:
            super.keyDown(with: ereignis)
        }
    }
}
