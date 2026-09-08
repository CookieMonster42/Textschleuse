import AppKit
import TextschleuseCore

/// Baut die Darstellung im Popup: der ganze Text, die Fundstellen darin als
/// Chips `Meier → PERSON_1`.
///
/// Früher waren lange Passagen ohne Fundstelle eingeklappt, damit das Fenster
/// kurz bleibt. Das ist wieder raus: eingeklappt heißt unsichtbar, und
/// unsichtbaren Text kannst du nicht markieren — genau das aber ist der Weg,
/// einen übersehenen Namen nachzutragen. Die Übersicht kommt jetzt aus der
/// Fundstellenliste daneben.
enum Chiptext {

    /// Trägt an jedem Stück der Darstellung, aus welchem Bereich des
    /// Originaltexts es stammt.
    ///
    /// Nötig, weil die Darstellung nicht der Originaltext ist: Chips schieben
    /// „→ PERSON_1" dazwischen, lange Passagen sind eingeklappt. Ohne diese
    /// Spur ließe sich eine Markierung mit der Maus nicht auf den Originaltext
    /// zurückrechnen.
    static let quellbereich = NSAttributedString.Key("textschleuse.quellbereich")

    struct Ergebnis {
        var text: NSAttributedString
        /// Wo jeder Fund in der aufgebauten Darstellung liegt. Für Auswahl und
        /// Scrollen.
        var bereiche: [UUID: NSRange]
    }

    /// Rechnet eine Markierung in der Darstellung auf den Originaltext zurück.
    static func originalBereich(
        fuer anzeige: NSRange,
        in text: NSAttributedString
    ) -> NSRange? {
        guard anzeige.length > 0, NSMaxRange(anzeige) <= text.length else { return nil }

        var kleinste = Int.max
        var groesste = Int.min

        text.enumerateAttribute(quellbereich, in: anzeige) { wert, angeschnitten, _ in
            guard let wert = wert as? NSValue else { return }
            let quelle = wert.rangeValue

            // `enumerateAttribute` schneidet den Lauf auf die Markierung zu.
            // Für die anteilige Rechnung wird der volle Lauf gebraucht, sonst
            // sieht jede Teilmarkierung wie ein Chip aus.
            var voll = NSRange(location: 0, length: 0)
            _ = text.attribute(quellbereich, at: angeschnitten.location, effectiveRange: &voll)

            let von: Int
            let bis: Int
            if voll.length == quelle.length {
                // Fließtext: Zeichen für Zeichen deckungsgleich, also anteilig.
                von = quelle.location + (angeschnitten.location - voll.location)
                bis = von + angeschnitten.length
            } else {
                // Ein Chip ist länger als sein Original, weil „→ PERSON_1"
                // dazukommt. Halbe Chips gibt es nicht: er zählt ganz.
                von = quelle.location
                bis = NSMaxRange(quelle)
            }
            kleinste = min(kleinste, von)
            groesste = max(groesste, bis)
        }

        guard kleinste != Int.max, groesste > kleinste else { return nil }
        return NSRange(location: kleinste, length: groesste - kleinste)
    }

    /// Der Originaltext, unverändert, mit farbig hinterlegten Fundstellen.
    ///
    /// Anders als `aufbauen` schiebt das nichts dazwischen. Genau deshalb
    /// lässt sich damit tippen: was dasteht, ist Zeichen für Zeichen der
    /// Originaltext, und eine Eingabe verschiebt nichts, was die App nicht
    /// nachvollziehen könnte. Welcher Deckname zu welcher Stelle gehört, sagt
    /// die Liste daneben.
    static func aufbauenOriginal(analyse: Analyse, ausgewaehlt: UUID?) -> Ergebnis {
        let original = analyse.original as NSString
        let ergebnis = NSMutableAttributedString(
            string: analyse.original,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor,
            ]
        )

        var bereiche: [UUID: NSRange] = [:]
        for fund in analyse.funde.sorted(by: { $0.bereich.location < $1.bereich.location }) {
            guard NSMaxRange(fund.bereich) <= original.length else { continue }
            bereiche[fund.id] = fund.bereich

            if fund.verworfen {
                ergebnis.addAttributes([
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: NSColor.tertiaryLabelColor,
                ], range: fund.bereich)
                continue
            }

            let farbe = farbe(fuer: fund)
            ergebnis.addAttributes([
                .backgroundColor: farbe.withAlphaComponent(fund.id == ausgewaehlt ? 0.34 : 0.16),
            ], range: fund.bereich)
            if fund.id == ausgewaehlt {
                ergebnis.addAttributes([
                    .underlineStyle: NSUnderlineStyle.thick.rawValue,
                    .underlineColor: farbe,
                ], range: fund.bereich)
            }
        }
        return Ergebnis(text: ergebnis, bereiche: bereiche)
    }

    static func aufbauen(analyse: Analyse, ausgewaehlt: UUID?) -> Ergebnis {
        let original = analyse.original as NSString
        let funde = analyse.funde.sorted { $0.bereich.location < $1.bereich.location }
        let ergebnis = NSMutableAttributedString()
        var bereiche: [UUID: NSRange] = [:]

        var position = 0
        for fund in funde {
            let luecke = NSRange(location: position, length: max(0, fund.bereich.location - position))
            ergebnis.append(lueckeAufbauen(original, luecke))

            let start = ergebnis.length
            ergebnis.append(chip(fuer: fund, ausgewaehlt: fund.id == ausgewaehlt))
            bereiche[fund.id] = NSRange(location: start, length: ergebnis.length - start)

            position = fund.bereich.location + fund.bereich.length
        }

        let rest = NSRange(location: position, length: max(0, original.length - position))
        ergebnis.append(lueckeAufbauen(original, rest))

        return Ergebnis(text: ergebnis, bereiche: bereiche)
    }

    // MARK: Bausteine

    private static func lueckeAufbauen(_ original: NSString, _ bereich: NSRange) -> NSAttributedString {
        guard bereich.length > 0 else { return NSAttributedString() }
        return NSAttributedString(
            string: original.substring(with: bereich),
            attributes: mitQuelle(fliesstext, bereich)
        )
    }

    private static func mitQuelle(
        _ attribute: [NSAttributedString.Key: Any],
        _ bereich: NSRange
    ) -> [NSAttributedString.Key: Any] {
        var kopie = attribute
        kopie[quellbereich] = NSValue(range: bereich)
        return kopie
    }

    private static func chip(fuer fund: Fund, ausgewaehlt: Bool) -> NSAttributedString {
        if fund.verworfen {
            return NSAttributedString(string: fund.text, attributes: mitQuelle(verworfen, fund.bereich))
        }

        let hintergrund = farbe(fuer: fund).withAlphaComponent(ausgewaehlt ? 0.34 : 0.16)
        let farbe = farbe(fuer: fund)

        var attribute: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .backgroundColor: hintergrund,
            .foregroundColor: NSColor.labelColor,
            // Unsichtbarer Verweis, damit ein Klick im Textfeld zum Fund
            // zurückführt. Die Darstellung bleibt unverändert, weil das
            // Textfeld keine Verweisauszeichnung zeichnet.
            .link: "fund://\(fund.id.uuidString)",
            quellbereich: NSValue(range: fund.bereich),
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

    /// Grün heißt: steht fest. Rot heißt: geraten, sieh nach. Blau heißt: von
    /// dir markiert.
    static func farbe(fuer fund: Fund) -> NSColor {
        if fund.quelle == .markierung { return .systemBlue }
        return fund.sicherheit == .sicher ? .systemGreen : .systemRed
    }

    private static var fliesstext: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.secondaryLabelColor,
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
