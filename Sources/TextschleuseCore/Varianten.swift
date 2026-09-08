import Foundation

/// Baut aus einem Begriff ein Suchmuster, das seine Schreibvarianten mitnimmt.
///
/// Abgedeckt sind: Groß- und Kleinschreibung, Umlautumschrift (Nyström,
/// Nystroem, Nystrom), Bindestrich statt Leerzeichen und angehängte deutsche
/// Beugungsendungen. Nicht abgedeckt sind Tippfehler; die laufen über
/// `AehnlichkeitsSuche` und gelten immer als Vermutung.
public enum Varianten {

    /// Endungen, die an einen Namen andocken dürfen, ohne dass ein anderes
    /// Wort daraus wird. `'s` ist der Deppenapostroph, der real vorkommt.
    static let beugungen = ["s", "es", "e", "n", "en", "ns", "'s", "\u{2019}s"]

    /// Zeichenfolgen, die füreinander einstehen. Längere Schlüssel zuerst
    /// prüfen, sonst frisst „s" das „ss" weg.
    private static let austausch: [(muster: String, alternativen: [String])] = [
        ("ae", ["ae", "ä"]),
        ("oe", ["oe", "ö"]),
        ("ue", ["ue", "ü"]),
        ("ss", ["ss", "ß"]),
        ("ä", ["ä", "ae", "a"]),
        ("ö", ["ö", "oe", "o"]),
        ("ü", ["ü", "ue", "u"]),
        ("ß", ["ß", "ss", "s"]),
    ]

    /// Ein fertiges Regex-Muster für den Begriff, inklusive Wortgrenzen.
    ///
    /// Die Wortgrenzen sind Lookarounds auf Buchstaben und Ziffern statt `\b`.
    /// `\b` zieht bei „Nyström." die Grenze anders als erwartet, sobald
    /// Umlaute im Spiel sind.
    public static func muster(fuer begriff: String, mitBeugung: Bool = true) -> String {
        let kern = kernMuster(fuer: begriff)
        guard !kern.isEmpty else { return "" }
        let endung = mitBeugung
            ? "(?:" + beugungen.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|") + ")?"
            : ""
        return "(?<![\\p{L}\\p{N}])" + kern + endung + "(?![\\p{L}\\p{N}])"
    }

    /// Der Teil ohne Wortgrenzen, damit man mehrere Begriffe kombinieren kann.
    static func kernMuster(fuer begriff: String) -> String {
        let getrimmt = begriff.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !getrimmt.isEmpty else { return "" }

        var ergebnis = ""
        var puffer = ""

        func pufferLeeren() {
            if !puffer.isEmpty {
                ergebnis += NSRegularExpression.escapedPattern(for: puffer)
                puffer = ""
            }
        }

        var index = getrimmt.startIndex
        zeichenSchleife: while index < getrimmt.endIndex {
            let zeichen = getrimmt[index]

            // Leerzeichen und Bindestriche sind austauschbar und dürfen sich
            // häufen: „Müller - Lüdenscheidt" trifft „Müller-Lüdenscheidt".
            if zeichen.isWhitespace || zeichen == "-" || zeichen == "\u{2013}" {
                pufferLeeren()
                ergebnis += "[\\s\\-\u{2013}]+"
                while index < getrimmt.endIndex,
                      getrimmt[index].isWhitespace || getrimmt[index] == "-" || getrimmt[index] == "\u{2013}" {
                    index = getrimmt.index(after: index)
                }
                continue
            }

            // Umschriften: erst die zweibuchstabigen prüfen.
            for (muster, alternativen) in austausch {
                if getrimmt[index...].lowercased().hasPrefix(muster) {
                    pufferLeeren()
                    ergebnis += "(?:" + alternativen.map {
                        NSRegularExpression.escapedPattern(for: $0)
                    }.joined(separator: "|") + ")"
                    index = getrimmt.index(index, offsetBy: muster.count)
                    continue zeichenSchleife
                }
            }

            puffer.append(zeichen)
            index = getrimmt.index(after: index)
        }
        pufferLeeren()
        return ergebnis
    }

    /// Fertig übersetzter, unempfindlicher Ausdruck. `nil`, wenn der Begriff
    /// leer ist oder das Muster nicht übersetzt werden kann.
    public static func regex(fuer begriff: String, mitBeugung: Bool = true) -> NSRegularExpression? {
        let muster = muster(fuer: begriff, mitBeugung: mitBeugung)
        guard !muster.isEmpty else { return nil }
        return try? NSRegularExpression(pattern: muster, options: [.caseInsensitive])
    }
}
