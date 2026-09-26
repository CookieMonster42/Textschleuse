import Foundation

/// Suchen und Ersetzen im Originaltext.
///
/// Ersetzt wird im Originaltext, nicht in der Anzeige: dort stehen die
/// Decknamen, und `PERSON_3F9A1C2D` soll niemand versehentlich mitersetzen.
/// Gesucht wird ohne Rücksicht auf Groß- und Kleinschreibung und auf
/// Umlautpünktchen — genauso, wie die Suchzeile ihre Treffer zählt.
public enum Textersatz {

    public struct Ergebnis: Equatable, Sendable {
        public var text: String
        public var anzahl: Int
    }

    static let optionen: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// Alle Vorkommen, von vorn nach hinten. Mit `wortgrenzen` zählt nur, was
    /// nicht mitten in einem Wort steht.
    public static func vorkommen(von begriff: String, in text: String, wortgrenzen: Bool) -> [NSRange] {
        let nsText = text as NSString
        guard !begriff.isEmpty, nsText.length > 0 else { return [] }
        var treffer: [NSRange] = []
        var start = 0
        while start < nsText.length {
            let rest = NSRange(location: start, length: nsText.length - start)
            let gefunden = nsText.range(of: begriff, options: optionen, range: rest)
            guard gefunden.location != NSNotFound else { break }
            if !wortgrenzen || stehtFrei(gefunden, in: nsText) {
                treffer.append(gefunden)
            }
            start = gefunden.location + max(1, gefunden.length)
        }
        return treffer
    }

    /// Ersetzt jedes Vorkommen.
    public static func ersetze(
        in text: String,
        begriff: String,
        durch ersatz: String,
        wortgrenzen: Bool
    ) -> Ergebnis {
        let treffer = vorkommen(von: begriff, in: text, wortgrenzen: wortgrenzen)
        guard !treffer.isEmpty else { return Ergebnis(text: text, anzahl: 0) }
        let neu = NSMutableString(string: text)
        // Von hinten nach vorn, damit die vorderen Bereiche stimmen bleiben.
        for bereich in treffer.reversed() {
            neu.replaceCharacters(in: bereich, with: ersatz)
        }
        return Ergebnis(text: neu as String, anzahl: treffer.count)
    }

    /// Ersetzt genau einen Bereich. Für „Ersetzen" auf den aktuellen Treffer.
    public static func ersetze(in text: String, bereich: NSRange, durch ersatz: String) -> Ergebnis {
        let nsText = text as NSString
        guard bereich.location != NSNotFound, bereich.length > 0,
              NSMaxRange(bereich) <= nsText.length
        else { return Ergebnis(text: text, anzahl: 0) }
        return Ergebnis(text: nsText.replacingCharacters(in: bereich, with: ersatz), anzahl: 1)
    }

    /// Links und rechts kein Buchstabe und keine Ziffer.
    private static func stehtFrei(_ bereich: NSRange, in text: NSString) -> Bool {
        let wortzeichen = CharacterSet.alphanumerics
        if bereich.location > 0 {
            let davor = text.substring(with: NSRange(location: bereich.location - 1, length: 1))
            if davor.unicodeScalars.allSatisfy(wortzeichen.contains) { return false }
        }
        let ende = NSMaxRange(bereich)
        if ende < text.length {
            let danach = text.substring(with: NSRange(location: ende, length: 1))
            if danach.unicodeScalars.allSatisfy(wortzeichen.contains) { return false }
        }
        return true
    }
}
