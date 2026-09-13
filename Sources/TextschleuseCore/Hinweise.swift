import Foundation

/// Die Zeilen, die über dem geschützten Text in der Zwischenablage landen.
public enum Hinweise {

    /// Geht an das KI-Werkzeug und steht immer über dem Text.
    public static let fuerModell = """
        [Hinweis] Der folgende Text ist anonymisiert. Ausdrücke wie \
        PERSON_3F9A1C7B2E4D6A0B5C, FIRMA_… oder IBAN_… sind Platzhalter für \
        echte Namen und Daten. Übernimm sie unverändert, Zeichen für Zeichen, \
        und schreibe sie nicht aus.
        """

    /// Geht an dich und steht nur da, wenn tatsächlich Ungeprüftes im Text ist.
    public static func fuerDich(unbekannte: [String]) -> String? {
        guard !unbekannte.isEmpty else { return nil }
        let liste = unbekannte.sorted(by: nummerischVor).joined(separator: ", ")
        return """
            [Achtung] Dieser Text enthält ungeprüfte Platzhalter: \(liste). \
            Prüfe sie in der Textschleuse und nimm sie ins Wörterbuch auf, \
            damit sie beim nächsten Mal richtig heißen.
            """
    }

    public static func vorspann(fuer analyse: Analyse) -> String {
        var bloecke = [fuerModell]
        let offene = analyse.aktiveFunde
            .filter { $0.platzhalter.hasPrefix(Kategorie.unbekannt.praefix) }
            .map(\.platzhalter)
        if let warnung = fuerDich(unbekannte: Array(Set(offene))) {
            bloecke.append(warnung)
        }
        return bloecke.joined(separator: "\n\n") + "\n\n---\n\n"
    }

    /// Alte Nummern der Größe nach — `UNBEKANNT_2` vor `UNBEKANNT_10` —,
    /// Zufallskennungen dahinter alphabetisch.
    static func nummerischVor(_ links: String, _ rechts: String) -> Bool {
        func nummer(_ text: String) -> Int {
            Int(text.split(separator: "_").last ?? "") ?? Int.max
        }
        if nummer(links) != nummer(rechts) { return nummer(links) < nummer(rechts) }
        return links < rechts
    }
}
