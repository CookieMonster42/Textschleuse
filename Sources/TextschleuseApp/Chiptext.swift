import AppKit
import TextschleuseCore

/// Baut die Darstellung im Popup: der Text mit den Fundstellen als Chips
/// `Meier → PERSON_1`, dazwischen die uninteressanten Passagen gefaltet.
enum Chiptext {

    /// Ab so vielen Zeichen ohne Fundstelle wird zusammengefaltet. Kürzere
    /// Lücken bleiben stehen, damit der Satz drumherum lesbar bleibt.
    static let faltGrenze = 260
    /// So viel Kontext bleibt links und rechts einer Fundstelle sichtbar.
    static let kontext = 90

    struct Ergebnis {
        var text: NSAttributedString
        /// Wo jeder Fund in der aufgebauten Darstellung liegt. Für Auswahl und
        /// Scrollen.
        var bereiche: [UUID: NSRange]
    }

    static func aufbauen(analyse: Analyse, ausgewaehlt: UUID?) -> Ergebnis {
        let original = analyse.original as NSString
        let funde = analyse.funde.sorted { $0.bereich.location < $1.bereich.location }
        let ergebnis = NSMutableAttributedString()
        var bereiche: [UUID: NSRange] = [:]

        var position = 0
        for fund in funde {
            let luecke = NSRange(location: position, length: max(0, fund.bereich.location - position))
            ergebnis.append(lueckeAufbauen(original, luecke, istAnfang: position == 0))

            let start = ergebnis.length
            ergebnis.append(chip(fuer: fund, ausgewaehlt: fund.id == ausgewaehlt))
            bereiche[fund.id] = NSRange(location: start, length: ergebnis.length - start)

            position = fund.bereich.location + fund.bereich.length
        }

        let rest = NSRange(location: position, length: max(0, original.length - position))
        ergebnis.append(lueckeAufbauen(original, rest, istAnfang: funde.isEmpty, istEnde: true))

        return Ergebnis(text: ergebnis, bereiche: bereiche)
    }

    // MARK: Bausteine

    private static func lueckeAufbauen(
        _ original: NSString,
        _ bereich: NSRange,
        istAnfang: Bool,
        istEnde: Bool = false
    ) -> NSAttributedString {
        guard bereich.length > 0 else { return NSAttributedString() }
        let inhalt = original.substring(with: bereich)

        guard bereich.length > faltGrenze else {
            return NSAttributedString(string: inhalt, attributes: fliesstext)
        }

        // Anfang und Ende der Lücke zeigen, die Mitte einklappen. Am
        // Textanfang und -ende reicht eine Seite.
        let vorne = istAnfang ? "" : String(inhalt.prefix(kontext))
        let hinten = istEnde ? "" : String(inhalt.suffix(kontext))
        let verborgen = bereich.length - vorne.count - hinten.count

        let zusammen = NSMutableAttributedString()
        if !vorne.isEmpty {
            zusammen.append(NSAttributedString(string: vorne, attributes: fliesstext))
        }
        zusammen.append(NSAttributedString(
            string: "  … \(verborgen) Zeichen …  ",
            attributes: gefaltet
        ))
        if !hinten.isEmpty {
            zusammen.append(NSAttributedString(string: hinten, attributes: fliesstext))
        }
        return zusammen
    }

    private static func chip(fuer fund: Fund, ausgewaehlt: Bool) -> NSAttributedString {
        if fund.verworfen {
            return NSAttributedString(string: fund.text, attributes: verworfen)
        }

        let farbe: NSColor = fund.sicherheit == .sicher
            ? NSColor.systemGreen
            : NSColor.systemRed
        let hintergrund = farbe.withAlphaComponent(ausgewaehlt ? 0.34 : 0.16)

        var attribute: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .backgroundColor: hintergrund,
            .foregroundColor: NSColor.labelColor,
            // Unsichtbarer Verweis, damit ein Klick im Textfeld zum Fund
            // zurückführt. Die Darstellung bleibt unverändert, weil das
            // Textfeld keine Verweisauszeichnung zeichnet.
            .link: "fund://\(fund.id.uuidString)",
        ]
        if ausgewaehlt {
            attribute[.underlineStyle] = NSUnderlineStyle.thick.rawValue
            attribute[.underlineColor] = farbe
        }

        let text = NSMutableAttributedString(string: " \(fund.text) ", attributes: attribute)
        var pfeilAttribute = attribute
        pfeilAttribute[.foregroundColor] = NSColor.secondaryLabelColor
        text.append(NSAttributedString(string: "→ ", attributes: pfeilAttribute))
        var platzhalterAttribute = attribute
        platzhalterAttribute[.foregroundColor] = farbe.blended(withFraction: 0.35, of: .labelColor) ?? farbe
        text.append(NSAttributedString(string: "\(fund.platzhalter) ", attributes: platzhalterAttribute))
        return text
    }

    // MARK: Stile

    private static var fliesstext: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
    }

    private static var gefaltet: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
    }

    private static var verworfen: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.tertiaryLabelColor,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
        ]
    }
}
