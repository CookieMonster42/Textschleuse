import Foundation

/// Die Sorte Begriff, die hinter einem Platzhalter steckt. Der `praefix` ist
/// das, was im Text landet: aus `person` wird `PERSON_7`.
///
/// Die Aufteilung ist bewusst feiner als „Nummer für alles". Ein Modell, das
/// `IBAN_1` liest, formuliert darum herum sinnvoller als bei `NUMMER_4`.
public enum Kategorie: String, Codable, CaseIterable, Sendable {
    case person
    case firma
    case ort
    case email
    case telefon
    case iban
    case bic
    case karte
    case datum
    case steuerId
    case nummer
    case begriff
    // Zuschaltbare Typen. Sie stehen immer im Enum, damit ein alter Text auch
    // dann zurückzudrehen ist, wenn die Erkennung inzwischen aus ist. Ob nach
    // ihnen gesucht wird, steuert `Woerterbuch.aktiveZusatzregeln`.
    case website
    case anschrift
    case aktenzeichen
    case kundennummer
    case vertragsnummer
    case unbekannt

    public var praefix: String {
        switch self {
        case .person: return "PERSON"
        case .firma: return "FIRMA"
        case .ort: return "ORT"
        case .email: return "EMAIL"
        case .telefon: return "TELEFON"
        case .iban: return "IBAN"
        case .bic: return "BIC"
        case .karte: return "KARTE"
        case .datum: return "DATUM"
        case .steuerId: return "STEUERID"
        case .nummer: return "NUMMER"
        case .begriff: return "BEGRIFF"
        case .website: return "WEBSITE"
        case .anschrift: return "ANSCHRIFT"
        case .aktenzeichen: return "AKTENZEICHEN"
        case .kundennummer: return "KUNDENNUMMER"
        case .vertragsnummer: return "VERTRAGSNUMMER"
        case .unbekannt: return "UNBEKANNT"
        }
    }

    /// Klartextname für die Oberfläche.
    public var anzeigename: String {
        switch self {
        case .person: return "Person"
        case .firma: return "Firma"
        case .ort: return "Ort"
        case .email: return "E-Mail"
        case .telefon: return "Telefon"
        case .iban: return "IBAN"
        case .bic: return "BIC"
        case .karte: return "Kartennummer"
        case .datum: return "Geburtsdatum"
        case .steuerId: return "Steuer-ID"
        case .nummer: return "Nummer"
        case .begriff: return "Sonstiges"
        case .website: return "Website"
        case .anschrift: return "Anschrift"
        case .aktenzeichen: return "Aktenzeichen"
        case .kundennummer: return "Kundennummer"
        case .vertragsnummer: return "Vertragsnummer"
        case .unbekannt: return "Unbekannt"
        }
    }

    /// Die fünf Typen, die im Popup auf den Zifferntasten 1 bis 5 liegen.
    public static let schnellwahl: [Kategorie] = [.person, .firma, .ort, .nummer, .begriff]

    /// Kategorien, die aus einer Regel entstehen und nicht aus einer Vermutung.
    /// Sie landen im Wörterbuch in der Sektion „automatisch erkannt".
    public var istRegelkategorie: Bool {
        switch self {
        case .email, .telefon, .iban, .bic, .karte, .datum, .steuerId,
             .website, .anschrift, .aktenzeichen, .kundennummer, .vertragsnummer:
            return true
        default:
            return false
        }
    }
}

/// Wie sicher ein Fund ist. Steuert die Farbe im Popup und die Frage, ob du
/// bestätigen musst.
public enum Sicherheit: String, Codable, Sendable {
    /// Regeltreffer oder Wörterbucheintrag. Wird ohne Nachfrage ersetzt, grün.
    case sicher
    /// Heuristik. Rot im Popup. Bestätigst du nicht, wird trotzdem ersetzt,
    /// dann als `UNBEKANNT_n`.
    case vermutung
}

public extension Kategorie {

    /// Was im Popup zur Wahl steht: die fünf festen Typen, dahinter die
    /// Kategorien der zugeschalteten Erkennungen.
    ///
    /// Wer „Anschrift" angeschaltet hat, will eine übersehene Adresse auch von
    /// Hand als ANSCHRIFT markieren können — nicht als „Sonstiges".
    static func zurWahl(mit woerterbuch: Woerterbuch) -> [Kategorie] {
        var reihe = schnellwahl
        for regel in woerterbuch.zusatzregeln where !reihe.contains(regel.kategorie) {
            reihe.append(regel.kategorie)
        }
        return reihe
    }

    /// Die Taste für den n-ten Platz in dieser Reihe: 1 bis 9, dann 0. Mehr
    /// als zehn Plätze gibt es nicht.
    static func taste(fuerPlatz platz: Int) -> String? {
        guard platz >= 0, platz < 10 else { return nil }
        return platz == 9 ? "0" : String(platz + 1)
    }

    /// Der Weg zurück: welcher Platz gehört zu dieser Ziffer?
    static func platz(fuerTaste taste: String) -> Int? {
        guard taste.count == 1, let ziffer = Int(taste) else { return nil }
        return ziffer == 0 ? 9 : ziffer - 1
    }
}
