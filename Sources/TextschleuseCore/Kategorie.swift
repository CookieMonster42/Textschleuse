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
        case .unbekannt: return "Unbekannt"
        }
    }

    /// Die fünf Typen, die im Popup auf den Zifferntasten 1 bis 5 liegen.
    public static let schnellwahl: [Kategorie] = [.person, .firma, .ort, .nummer, .begriff]

    /// Kategorien, die aus einer Regel entstehen und nicht aus einer Vermutung.
    /// Sie landen im Wörterbuch in der Sektion „automatisch erkannt".
    public var istRegelkategorie: Bool {
        switch self {
        case .email, .telefon, .iban, .bic, .karte, .datum, .steuerId: return true
        default: return false
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
