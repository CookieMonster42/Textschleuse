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

    /// Markiert die Zeichen, die die App dazugeschrieben hat: den Pfeil und
    /// den Decknamen. Sie gehören nicht zum Originaltext, lassen sich nicht
    /// bearbeiten und fallen beim Zurückrechnen weg.
    static let istPlatzhalter = NSAttributedString.Key("textschleuse.istPlatzhalter")

    struct Ergebnis {
        var text: NSAttributedString
        /// Wo jeder Fund in der aufgebauten Darstellung liegt. Für Auswahl und
        /// Scrollen.
        var bereiche: [UUID: NSRange]
    }

    /// Ein Stück Text, das als Chip gezeichnet wird — egal, ob es aus dem
    /// Schützen kommt (`Nyström → PERSON_…`) oder aus dem Rückweg
    /// (`PERSON_… → Nyström`).
    struct Chip {
        var id: UUID
        /// Lage im Originaltext.
        var bereich: NSRange
        /// Der Wortlaut, so wie er im Text steht.
        var text: String
        /// Was hinter dem Pfeil steht. Leer heißt: kein Pfeil, nur Farbe.
        var deckname: String
        var farbe: NSColor
        /// Durchgestrichen und blass: verworfen, bleibt Klartext.
        var durchgestrichen: Bool = false
    }

    /// Was eine Eingabe im Textfeld darf. Siehe `pruefeAenderung`.
    enum Aenderung: Equatable {
        case erlaubt
        case verboten
        /// Ein Löschen, das einen Chip anschneidet, wird auf den ganzen Chip
        /// ausgeweitet: der Chip ist ein Wort, kein Buchstabenhaufen.
        case ausweiten(NSRange)
    }

    /// Entscheidet, ob eine Änderung an der Darstellung erlaubt ist.
    ///
    /// Erlaubt ist alles am Originaltext. Die Zutat der App — Pfeil und
    /// Deckname — lässt sich nicht buchstabenweise ändern, aber löschen: wer
    /// alles markiert und ⌫ drückt, will einen leeren Text, und wer hinter
    /// einem Chip ⌫ drückt, will den Chip weg. Im ersten Fall liegt jeder
    /// Deckname ganz in der Markierung, im zweiten wird das Löschen auf den
    /// ganzen Chip ausgeweitet. Nur Tippen mitten im Decknamen bleibt
    /// verboten.
    static func pruefeAenderung(
        bereich: NSRange,
        ersatz: String?,
        in anzeige: NSAttributedString,
        chips: [UUID: NSRange]
    ) -> Aenderung {
        guard NSMaxRange(bereich) <= anzeige.length else { return .verboten }

        if bereich.length == 0 {
            // Einfügemarke: nur mitten im Deckname sperren. An seinen Rändern
            // soll man den Namen davor noch verlängern können.
            let vorher = bereich.location > 0
                && anzeige.attribute(istPlatzhalter, at: bereich.location - 1, effectiveRange: nil) != nil
            let danach = bereich.location < anzeige.length
                && anzeige.attribute(istPlatzhalter, at: bereich.location, effectiveRange: nil) != nil
            return vorher && danach ? .verboten : .erlaubt
        }

        var angeschnitten = false
        var beruehrt = false
        anzeige.enumerateAttribute(istPlatzhalter, in: bereich) { wert, lauf, _ in
            guard wert != nil else { return }
            beruehrt = true
            var voll = NSRange(location: 0, length: 0)
            _ = anzeige.attribute(istPlatzhalter, at: lauf.location, effectiveRange: &voll)
            if voll.location < bereich.location || NSMaxRange(voll) > NSMaxRange(bereich) {
                angeschnitten = true
            }
        }
        guard beruehrt else { return .erlaubt }
        guard angeschnitten else { return .erlaubt }
        guard (ersatz ?? "").isEmpty else { return .verboten }

        var erweitert = bereich
        for chip in chips.values where NSIntersectionRange(chip, bereich).length > 0 {
            erweitert = NSUnionRange(erweitert, chip)
        }
        return .ausweiten(erweitert)
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
                // Hier ist die Darstellung der Originaltext, Zeichen für
                // Zeichen. Die Spur muss trotzdem dran sein, sonst findet eine
                // Markierung ihren Platz im Original nicht.
                quellbereich: NSValue(range: NSRange(location: 0, length: original.length)),
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
        let chips = analyse.funde.map { fund in
            Chip(
                id: fund.id,
                bereich: fund.bereich,
                text: fund.text,
                deckname: fund.platzhalter,
                farbe: farbe(fuer: fund),
                durchgestrichen: fund.verworfen
            )
        }
        return aufbauen(original: analyse.original, chips: chips, ausgewaehlt: ausgewaehlt)
    }

    static func aufbauen(original text: String, chips: [Chip], ausgewaehlt: UUID?) -> Ergebnis {
        let original = text as NSString
        let sortiert = chips
            .filter { NSMaxRange($0.bereich) <= original.length }
            .sorted { $0.bereich.location < $1.bereich.location }
        let ergebnis = NSMutableAttributedString()
        var bereiche: [UUID: NSRange] = [:]

        var position = 0
        for chip in sortiert where chip.bereich.location >= position {
            let luecke = NSRange(location: position, length: max(0, chip.bereich.location - position))
            ergebnis.append(lueckeAufbauen(original, luecke))

            let start = ergebnis.length
            ergebnis.append(self.chip(chip, ausgewaehlt: chip.id == ausgewaehlt))
            bereiche[chip.id] = NSRange(location: start, length: ergebnis.length - start)

            position = NSMaxRange(chip.bereich)
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

    private static func chip(_ chip: Chip, ausgewaehlt: Bool) -> NSAttributedString {
        if chip.durchgestrichen {
            return NSAttributedString(string: chip.text, attributes: mitQuelle(verworfen, chip.bereich))
        }

        let farbe = chip.farbe
        let hintergrund = farbe.withAlphaComponent(ausgewaehlt ? 0.34 : 0.16)

        var attribute: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .backgroundColor: hintergrund,
            .foregroundColor: NSColor.labelColor,
            // Unsichtbarer Verweis, damit ein Klick im Textfeld zum Fund
            // zurückführt. Die Darstellung bleibt unverändert, weil das
            // Textfeld keine Verweisauszeichnung zeichnet.
            .link: "fund://\(chip.id.uuidString)",
            quellbereich: NSValue(range: chip.bereich),
        ]
        if ausgewaehlt {
            attribute[.underlineStyle] = NSUnderlineStyle.thick.rawValue
            attribute[.underlineColor] = farbe
        }

        // Zwei Stücke: vorn der Originaltext, dahinter die Zutat der App. Nur
        // das vordere trägt die Quellspur, nur es lässt sich bearbeiten.
        //
        // Kein Leerzeichen als Polster links und rechts. Das sah gefälliger
        // aus, hat aber verdeckt, was im Text steht: ob nach dem Namen ein
        // Leerzeichen kommt oder gleich das Komma, war nicht zu sehen. Jetzt
        // endet der Chip mit dem Decknamen, und was folgt, ist Originaltext.
        var dekoration = attribute
        dekoration[istPlatzhalter] = true
        dekoration[.foregroundColor] = NSColor.secondaryLabelColor
        dekoration.removeValue(forKey: quellbereich)

        let text = NSMutableAttributedString(string: chip.text, attributes: attribute)
        guard !chip.deckname.isEmpty else { return text }

        var decknameAttribute = dekoration
        decknameAttribute[.foregroundColor] = farbe.blended(withFraction: 0.35, of: .labelColor) ?? farbe
        text.append(NSAttributedString(string: " → ", attributes: dekoration))
        text.append(NSAttributedString(string: chip.deckname, attributes: decknameAttribute))
        return text
    }

    /// Löscht den Bereich, sobald die laufende Eingabe abgeschlossen ist.
    /// Mitten in `shouldChangeText` darf der Speicher nicht angefasst werden.
    static func loescheSpaeter(_ bereich: NSRange, in ansicht: NSTextView) {
        DispatchQueue.main.async {
            guard NSMaxRange(bereich) <= ansicht.string.utf16.count,
                  ansicht.shouldChangeText(in: bereich, replacementString: "")
            else { return }
            ansicht.textStorage?.replaceCharacters(in: bereich, with: "")
            ansicht.didChangeText()
            ansicht.setSelectedRange(NSRange(location: bereich.location, length: 0))
        }
    }

    // MARK: Zurückrechnen

    /// Der Originaltext aus einer Darstellung: alles, was die App nicht selbst
    /// dazugeschrieben hat.
    static func originaltext(aus anzeige: NSAttributedString) -> String {
        let ganz = NSRange(location: 0, length: anzeige.length)
        let roh = anzeige.string as NSString
        var ergebnis = ""
        anzeige.enumerateAttribute(istPlatzhalter, in: ganz) { wert, bereich, _ in
            guard wert == nil else { return }
            ergebnis += roh.substring(with: bereich)
        }
        return ergebnis
    }

    /// Wie viele Originalzeichen vor dieser Stelle in der Darstellung liegen.
    static func originalPosition(fuer anzeigePosition: Int, in anzeige: NSAttributedString) -> Int {
        let bis = min(max(0, anzeigePosition), anzeige.length)
        guard bis > 0 else { return 0 }
        var gezaehlt = 0
        anzeige.enumerateAttribute(istPlatzhalter, in: NSRange(location: 0, length: bis)) { wert, bereich, _ in
            guard wert == nil else { return }
            gezaehlt += bereich.length
        }
        return gezaehlt
    }

    /// Der Weg zurück: wo in der Darstellung steht das n-te Originalzeichen?
    static func anzeigePosition(fuer originalPosition: Int, in anzeige: NSAttributedString) -> Int {
        var gezaehlt = 0
        var treffer = anzeige.length
        anzeige.enumerateAttribute(
            istPlatzhalter,
            in: NSRange(location: 0, length: anzeige.length)
        ) { wert, bereich, weiter in
            guard wert == nil else { return }
            if gezaehlt + bereich.length >= originalPosition {
                treffer = bereich.location + (originalPosition - gezaehlt)
                weiter.pointee = true
                return
            }
            gezaehlt += bereich.length
        }
        return min(treffer, anzeige.length)
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
