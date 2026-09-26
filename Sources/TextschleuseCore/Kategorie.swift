import Foundation

/// Die Sorte Begriff, die hinter einem Platzhalter steckt. Der `praefix` ist
/// das, was im Text landet: aus `person` wird `PERSON_7`.
///
/// Die Aufteilung ist bewusst feiner als „Nummer für alles". Ein Modell, das
/// `IBAN_1` liest, formuliert darum herum sinnvoller als bei `NUMMER_4`.
public enum Kategorie: String, Codable, CaseIterable, Sendable {
    case person
    case firma
    // Drei Sorten Firma. Ein Modell, das KUNDE_… und DIENSTLEISTER_… liest,
    // versteht die Rollen im Text; bei zweimal FIRMA_… müsste es raten. In
    // den Listen stehen sie unter „Firma › Kunde".
    case kunde
    case dienstleister
    case tool
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
        case .kunde: return "KUNDE"
        case .dienstleister: return "DIENSTLEISTER"
        case .tool: return "TOOL"
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
        case .kunde: return "Kunde"
        case .dienstleister: return "Dienstleister"
        case .tool: return "Tool"
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

    /// Die acht Typen auf den Zifferntasten 1 bis 8. Die ersten fünf lagen
    /// von Anfang an so und wurden beim Erweitern nicht verschoben.
    public static let schnellwahl: [Kategorie] = [
        .person, .firma, .ort, .nummer, .begriff, .kunde, .dienstleister, .tool,
    ]

    /// Die Kategorie, unter der diese in den Listen einsortiert wird. Nur
    /// die drei Sorten Firma haben eine.
    public var oberkategorie: Kategorie? {
        switch self {
        case .kunde, .dienstleister, .tool: return .firma
        default: return nil
        }
    }

    /// „Firma › Kunde" für die Listen, sonst der Anzeigename.
    public var anzeigepfad: String {
        guard let oben = oberkategorie else { return anzeigename }
        return "\(oben.anzeigename) › \(anzeigename)"
    }

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

    /// Was im Popup zur Wahl steht: die acht festen Typen auf den Ziffern,
    /// dahinter die Kategorien der zugeschalteten Erkennungen — die nur als
    /// Knopf, denn mehr als acht Ziffern merkt sich niemand.
    ///
    /// Wer „Anschrift" angeschaltet hat, will eine übersehene Adresse auch von
    /// Hand als ANSCHRIFT markieren können — nicht als „Sonstiges".
    static func zurWahl(mit woerterbuch: Woerterbuch) -> [Kategorie] {
        schnellwahl + zusatzZurWahl(mit: woerterbuch)
    }

    /// Nur die zugeschalteten Erkennungen, in der Reihenfolge der Einstellungen.
    static func zusatzZurWahl(mit woerterbuch: Woerterbuch) -> [Kategorie] {
        var reihe: [Kategorie] = []
        for regel in woerterbuch.zusatzregeln
        where !schnellwahl.contains(regel.kategorie) && !reihe.contains(regel.kategorie) {
            reihe.append(regel.kategorie)
        }
        return reihe
    }

    /// Die Taste für den n-ten Platz in der Reihe: 1 bis 8, dahinter keine.
    static func taste(fuerPlatz platz: Int) -> String? {
        guard schnellwahl.indices.contains(platz) else { return nil }
        return String(platz + 1)
    }

    /// Der Weg zurück: welcher Platz gehört zu dieser Ziffer?
    static func platz(fuerTaste taste: String) -> Int? {
        guard taste.count == 1, let ziffer = Int(taste),
              schnellwahl.indices.contains(ziffer - 1)
        else { return nil }
        return ziffer - 1
    }
}
