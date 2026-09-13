import Foundation

/// Erkennungen, die du in den Einstellungen zuschaltest.
///
/// Sie sind aus, bis du sie anschaltest. Anders als E-Mail oder IBAN sind das
/// keine Formate mit Prüfsumme, sondern Muster, die je nach Haus anders
/// aussehen — ein Aktenzeichen bei einer Sparkasse folgt nicht derselben Form
/// wie eines bei Gericht. Was hier greift, ist eine begründete Vermutung mit
/// klarem Anker, kein Beweis.
public struct Zusatzregel: Regel, Sendable, Identifiable {
    public var id: String { kennung }

    /// Bleibt stabil, auch wenn sich Name oder Muster ändern. Danach merkt
    /// sich das Wörterbuch, was angeschaltet ist.
    public let kennung: String
    public let name: String
    public let erklaerung: String
    public let kategorie: Kategorie
    /// Das Suchmuster. Gibt es eine Gruppe 1, wird nur sie ersetzt — bei
    /// „Kundennummer 4711" soll das Wort „Kundennummer" stehen bleiben,
    /// sonst versteht die KI die Frage nicht mehr.
    let muster: String
    let optionen: NSRegularExpression.Options

    public func finde(in text: NSString) -> [Fund] {
        RegexWerkzeug.treffer(muster, in: text, optionen: optionen).compactMap { treffer in
            let bereich = treffer.numberOfRanges > 1 && treffer.range(at: 1).location != NSNotFound
                ? treffer.range(at: 1)
                : treffer.range
            guard bereich.length > 0 else { return nil }
            return Fund(
                bereich: bereich,
                text: text.substring(with: bereich),
                kategorie: kategorie,
                sicherheit: .sicher,
                quelle: .regel
            )
        }
    }
}

public extension Zusatzregel {

    /// Alle vorbereiteten Erkennungen, in der Reihenfolge der Einstellungen.
    static let alle: [Zusatzregel] = [website, anschrift, aktenzeichen, kundennummer, vertragsnummer]

    static func mit(kennung: String) -> Zusatzregel? {
        alle.first { $0.kennung == kennung }
    }

    /// Web-Adressen. Nackte Domains ohne `www` bleiben außen vor — sonst
    /// würde jedes „z.B." und jede Dateiendung zur Website.
    static let website = Zusatzregel(
        kennung: "website",
        name: "Website",
        erklaerung: "Adressen mit http://, https:// oder www. samt Pfad. "
            + "Eine Domain ohne Vorsatz wird nicht erkannt.",
        kategorie: .website,
        muster: "(?:https?://|www\\.)[\\w\\-]+(?:\\.[\\w\\-]+)+(?:/[^\\s<>\"'\\)]*)?",
        optionen: [.caseInsensitive]
    )

    /// Straße mit Hausnummer. Der Anker ist das Grundwort am Wortende.
    static let anschrift = Zusatzregel(
        kennung: "anschrift",
        name: "Anschrift",
        erklaerung: "Straße mit Hausnummer, etwa „Wiesenweg 14b\". "
            + "Erkannt wird an Endungen wie -straße, -weg, -platz, -allee.",
        kategorie: .anschrift,
        muster: "\\b[A-ZÄÖÜ][\\wäöüßA-ZÄÖÜ\\-\\.]*"
            + "(?:stra(?:ß|ss)e|str\\.|weg|platz|allee|gasse|ring|damm|ufer|chaussee)"
            // Der Zusatz hängt direkt an: „14b", nicht „14 b". Mit einem
            // erlaubten Leerzeichen dazwischen schluckt das Muster das Komma
            // und das nächste Wort.
            + "\\s+\\d+[a-zA-Z]?\\b",
        optionen: []
    )

    /// Gerichtliche Aktenzeichen („12 O 345/21") und alles hinter „Az.".
    static let aktenzeichen = Zusatzregel(
        kennung: "aktenzeichen",
        name: "Aktenzeichen",
        erklaerung: "Gerichtsform wie „12 O 345/21\" und alles, was hinter "
            + "„Az.\" oder „Aktenzeichen\" steht.",
        kategorie: .aktenzeichen,
        muster: "(?:\\b\\d{1,4}\\s+[A-Z]{1,3}\\s+\\d{1,5}/\\d{2,4}\\b)"
            // Ohne Leerzeichen in der Zeichenklasse: sonst läuft der Treffer
            // hinter dem Aktenzeichen in den nächsten Satz weiter.
            + "|(?:(?:aktenzeichen|az)\\.?\\s*:?\\s*([A-Z0-9][A-Z0-9\\-/]{1,20}[A-Z0-9]))",
        optionen: [.caseInsensitive]
    )

    static let kundennummer = Zusatzregel(
        kennung: "kundennummer",
        name: "Kundennummer",
        erklaerung: "Der Wert hinter „Kundennummer\", „Kunden-Nr.\" oder „Kd.-Nr.\". "
            + "Das Wort davor bleibt stehen.",
        kategorie: .kundennummer,
        muster: "(?:kunden-?\\s?(?:nummer|nr)|kd\\.?-?\\s?nr)\\.?\\s*:?\\s*"
            + "([A-Z0-9][A-Z0-9\\-/]{2,})",
        optionen: [.caseInsensitive]
    )

    static let vertragsnummer = Zusatzregel(
        kennung: "vertragsnummer",
        name: "Vertragsnummer",
        erklaerung: "Der Wert hinter „Vertragsnummer\", „Vertrags-Nr.\" oder "
            + "„Policennummer\". Das Wort davor bleibt stehen.",
        kategorie: .vertragsnummer,
        muster: "(?:vertrags?-?\\s?(?:nummer|nr)|policen?-?\\s?(?:nummer|nr))\\.?\\s*:?\\s*"
            + "([A-Z0-9][A-Z0-9\\-/]{2,})",
        optionen: [.caseInsensitive]
    )
}
