import Foundation

/// Eine Erkennungsregel. Jede Regel sieht den ganzen Text und meldet, was sie
/// findet. Überschneidungen räumt später `ohneUeberschneidungen()` auf.
public protocol Regel: Sendable {
    var kategorie: Kategorie { get }
    func finde(in text: NSString) -> [Fund]
}

// MARK: - Werkzeug

enum RegexWerkzeug {
    static func treffer(_ muster: String, in text: NSString, optionen: NSRegularExpression.Options = []) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: muster, options: optionen) else { return [] }
        return regex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
    }

    /// Die letzten `laenge` Zeichen vor einer Fundstelle, klein geschrieben.
    /// Damit prüfen die Regeln, ob ein Signalwort davorsteht.
    static func davor(_ bereich: NSRange, in text: NSString, laenge: Int = 30) -> String {
        let start = max(0, bereich.location - laenge)
        let fenster = NSRange(location: start, length: bereich.location - start)
        return text.substring(with: fenster).lowercased()
    }

    static func enthaeltSignalwort(_ umfeld: String, _ woerter: [String]) -> Bool {
        woerter.contains { umfeld.contains($0) }
    }
}

// MARK: - E-Mail

public struct EmailRegel: Regel {
    public let kategorie = Kategorie.email
    public init() {}

    static let muster = "[A-Z0-9._%+\\-]+@[A-Z0-9.\\-]+\\.[A-Z]{2,}"

    public func finde(in text: NSString) -> [Fund] {
        RegexWerkzeug.treffer(Self.muster, in: text, optionen: [.caseInsensitive]).map { treffer in
            Fund(
                bereich: treffer.range,
                text: text.substring(with: treffer.range),
                kategorie: .email,
                sicherheit: .sicher,
                quelle: .regel
            )
        }
    }
}

// MARK: - IBAN

public struct IbanRegel: Regel {
    public let kategorie = Kategorie.iban
    public init() {}

    static let muster = "\\b[A-Z]{2}\\d{2}(?:[ ]?[A-Z0-9]{4}){2,7}(?:[ ]?[A-Z0-9]{1,3})?\\b"

    public func finde(in text: NSString) -> [Fund] {
        RegexWerkzeug.treffer(Self.muster, in: text).compactMap { treffer in
            let roh = text.substring(with: treffer.range)
            guard Self.pruefsummeStimmt(roh) else { return nil }
            return Fund(
                bereich: treffer.range,
                text: roh,
                kategorie: .iban,
                sicherheit: .sicher,
                quelle: .regel
            )
        }
    }

    /// Modulo-97-Prüfung nach ISO 13616. Ohne sie hält die Regel jede längere
    /// Kombination aus zwei Buchstaben und Ziffern für eine Kontonummer.
    public static func pruefsummeStimmt(_ iban: String) -> Bool {
        let sauber = iban.replacingOccurrences(of: " ", with: "").uppercased()
        guard sauber.count >= 15, sauber.count <= 34 else { return false }
        let umgestellt = String(sauber.dropFirst(4)) + String(sauber.prefix(4))

        var rest = 0
        for zeichen in umgestellt {
            let stelle: Int
            if let ziffer = zeichen.wholeNumberValue, zeichen.isNumber {
                stelle = ziffer
            } else if let ascii = zeichen.asciiValue, zeichen.isLetter {
                stelle = Int(ascii - 65) + 10
            } else {
                return false
            }
            rest = stelle < 10 ? (rest * 10 + stelle) % 97 : (rest * 100 + stelle) % 97
        }
        return rest == 1
    }
}

// MARK: - BIC

public struct BicRegel: Regel {
    public let kategorie = Kategorie.bic
    public init() {}

    static let muster = "\\b[A-Z]{4}[A-Z]{2}[A-Z0-9]{2}(?:[A-Z0-9]{3})?\\b"

    /// Ohne Länderprüfung hält die Regel jedes achtstellige Wort in
    /// Großbuchstaben für eine Bankleitzahl, etwa in einer Betreffzeile.
    static let laendercodes: Set<String> = [
        "DE", "AT", "CH", "LU", "LI", "NL", "BE", "FR", "IT", "ES", "PT", "GB",
        "IE", "DK", "SE", "NO", "FI", "PL", "CZ", "SK", "HU", "SI", "HR", "GR",
        "US", "CA", "JP", "CN", "AU", "SG", "HK", "AE", "TR", "RO", "BG", "EE",
        "LV", "LT", "CY", "MT", "IS",
    ]

    public func finde(in text: NSString) -> [Fund] {
        RegexWerkzeug.treffer(Self.muster, in: text).compactMap { treffer in
            let roh = text.substring(with: treffer.range)
            let land = String(roh.dropFirst(4).prefix(2))
            guard Self.laendercodes.contains(land) else { return nil }
            return Fund(
                bereich: treffer.range,
                text: roh,
                kategorie: .bic,
                sicherheit: .sicher,
                quelle: .regel
            )
        }
    }
}

// MARK: - Kartennummer

public struct KartenRegel: Regel {
    public let kategorie = Kategorie.karte
    public init() {}

    static let muster = "\\b(?:\\d[ \\-]?){12,18}\\d\\b"

    public func finde(in text: NSString) -> [Fund] {
        RegexWerkzeug.treffer(Self.muster, in: text).compactMap { treffer in
            let roh = text.substring(with: treffer.range)
            let ziffern = roh.filter(\.isNumber)
            guard (13...19).contains(ziffern.count), Self.luhnStimmt(ziffern) else { return nil }
            return Fund(
                bereich: treffer.range,
                text: roh,
                kategorie: .karte,
                sicherheit: .sicher,
                quelle: .regel
            )
        }
    }

    /// Luhn-Prüfziffer. Filtert Rechnungs- und Kundennummern heraus, die
    /// zufällig 16 Stellen haben.
    public static func luhnStimmt(_ ziffern: String) -> Bool {
        var summe = 0
        var verdoppeln = false
        for zeichen in ziffern.reversed() {
            guard let wert = zeichen.wholeNumberValue else { return false }
            if verdoppeln {
                let doppelt = wert * 2
                summe += doppelt > 9 ? doppelt - 9 : doppelt
            } else {
                summe += wert
            }
            verdoppeln.toggle()
        }
        return summe % 10 == 0
    }
}

// MARK: - Telefon

public struct TelefonRegel: Regel {
    public let kategorie = Kategorie.telefon
    public init() {}

    /// Mit Ländervorwahl. Gilt immer als sicher.
    static let musterInternational = "(?:\\+|00)\\d{1,3}[ /\\-]?(?:\\(?\\d{1,6}\\)?[ /\\-]?)?\\d{3,}(?:[ /\\-]?\\d{2,})*"
    /// Ohne Ländervorwahl: führende Null und mindestens sechs weitere Stellen.
    /// Die Vorwahl darf in Klammern stehen, das ist im Schriftverkehr üblich.
    static let musterNational = "\\(?\\b0\\d{2,5}\\)?[ /\\-]?\\d{3,}(?:[ /\\-]?\\d{2,})*\\b"

    static let signalwoerter = ["tel", "telefon", "fon", "mobil", "handy", "durchwahl", "fax", "rufnummer", "☎"]

    public func finde(in text: NSString) -> [Fund] {
        var funde: [Fund] = []

        for treffer in RegexWerkzeug.treffer(Self.musterInternational, in: text) {
            let roh = text.substring(with: treffer.range)
            guard roh.filter(\.isNumber).count >= 7 else { continue }
            funde.append(Fund(
                bereich: treffer.range,
                text: roh,
                kategorie: .telefon,
                sicherheit: .sicher,
                quelle: .regel
            ))
        }

        for treffer in RegexWerkzeug.treffer(Self.musterNational, in: text) {
            let roh = text.substring(with: treffer.range)
            let ziffern = roh.filter(\.isNumber).count
            guard ziffern >= 7, ziffern <= 15 else { continue }
            let umfeld = RegexWerkzeug.davor(treffer.range, in: text)
            let hatSignal = RegexWerkzeug.enthaeltSignalwort(umfeld, Self.signalwoerter)
            // Gliederung durch Leerzeichen, Schrägstrich oder Bindestrich ist
            // das zweite Indiz. Ein durchgehender Ziffernblock ohne Signalwort
            // ist genauso oft eine Vorgangsnummer.
            let istGegliedert = roh.contains(" ") || roh.contains("/") || roh.contains("-")
            funde.append(Fund(
                bereich: treffer.range,
                text: roh,
                kategorie: .telefon,
                sicherheit: (hatSignal || istGegliedert) ? .sicher : .vermutung,
                quelle: .regel
            ))
        }

        return funde
    }
}

// MARK: - Geburtsdatum

public struct GeburtsdatumRegel: Regel {
    public let kategorie = Kategorie.datum
    public init() {}

    static let musterZiffern = "\\b(\\d{1,2})[.\\-/](\\d{1,2})[.\\-/](\\d{2,4})\\b"
    static let musterAusgeschrieben =
        "\\b(\\d{1,2})\\.?\\s*(Januar|Februar|März|Maerz|April|Mai|Juni|Juli|August|September|Oktober|November|Dezember)\\s+(\\d{4})\\b"

    static let signalwoerter = ["geb", "geboren", "geburtsdatum", "geburtstag", "*", "jahrgang"]

    public func finde(in text: NSString) -> [Fund] {
        var funde: [Fund] = []
        for muster in [Self.musterZiffern, Self.musterAusgeschrieben] {
            for treffer in RegexWerkzeug.treffer(muster, in: text, optionen: [.caseInsensitive]) {
                let roh = text.substring(with: treffer.range)
                let umfeld = RegexWerkzeug.davor(treffer.range, in: text, laenge: 25)
                let hatSignal = RegexWerkzeug.enthaeltSignalwort(umfeld, Self.signalwoerter)
                // Ohne Signalwort bleibt offen, ob das ein Geburtstag oder eine
                // Frist ist. Ersetzt wird trotzdem, aber nur als Vermutung, denn
                // ein durchnummeriertes Fristendatum macht den Text unlesbar.
                guard hatSignal || Self.jahrPasstZuGeburt(roh) else { continue }
                funde.append(Fund(
                    bereich: treffer.range,
                    text: roh,
                    kategorie: .datum,
                    sicherheit: hatSignal ? .sicher : .vermutung,
                    quelle: .regel
                ))
            }
        }
        return funde
    }

    /// Vierstellige Jahreszahl, die mindestens 14 Jahre zurückliegt. Termine
    /// und Fristen liegen fast immer näher an heute.
    static func jahrPasstZuGeburt(_ text: String) -> Bool {
        guard let jahrText = text.split(whereSeparator: { !$0.isNumber }).last,
              jahrText.count == 4,
              let jahr = Int(jahrText)
        else { return false }
        let heute = Calendar(identifier: .gregorian).component(.year, from: Date())
        return jahr >= 1900 && jahr <= heute - 14
    }
}

// MARK: - Steuer-Identifikationsnummer

public struct SteuerIdRegel: Regel {
    public let kategorie = Kategorie.steuerId
    public init() {}

    static let muster = "\\b\\d{2}[ ]?\\d{3}[ ]?\\d{3}[ ]?\\d{3}\\b|\\b\\d{11}\\b"
    static let signalwoerter = ["steuer-id", "steuerid", "steuer-identifikationsnummer",
                                "steueridentifikationsnummer", "idnr", "id-nr", "steuernummer", "st.-nr"]

    public func finde(in text: NSString) -> [Fund] {
        // Elf Ziffern ohne Kontext sind genauso oft eine Vorgangsnummer.
        // Deshalb zählt hier ausschließlich das Signalwort davor.
        RegexWerkzeug.treffer(Self.muster, in: text).compactMap { treffer in
            let umfeld = RegexWerkzeug.davor(treffer.range, in: text, laenge: 40)
            guard RegexWerkzeug.enthaeltSignalwort(umfeld, Self.signalwoerter) else { return nil }
            return Fund(
                bereich: treffer.range,
                text: text.substring(with: treffer.range),
                kategorie: .steuerId,
                sicherheit: .sicher,
                quelle: .regel
            )
        }
    }
}

// MARK: - Sammlung

public enum Regelwerk {
    public static let alle: [Regel] = [
        EmailRegel(),
        IbanRegel(),
        BicRegel(),
        KartenRegel(),
        SteuerIdRegel(),
        TelefonRegel(),
        GeburtsdatumRegel(),
    ]

    /// Die Regeln greifen ineinander: die Ziffernblöcke einer IBAN sehen für
    /// sich genommen aus wie Telefonnummern. Deshalb fällt hier schon die
    /// Entscheidung, welcher Treffer gewinnt — der längere.
    ///
    /// `zusaetzlich` sind die in den Einstellungen angeschalteten Erkennungen.
    /// Sie laufen im selben Durchgang, damit eine Website nicht mit der
    /// E-Mail-Adresse darin kollidiert.
    public static func finde(in text: String, zusaetzlich: [Zusatzregel] = []) -> [Fund] {
        let nsText = text as NSString
        return (alle + zusaetzlich).flatMap { $0.finde(in: nsText) }.ohneUeberschneidungen()
    }
}
