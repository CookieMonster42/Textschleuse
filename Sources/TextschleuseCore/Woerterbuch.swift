import Foundation

/// Eine andere Schreibweise derselben Sache. „Herr Nyström" hängt als Alias an
/// „Thorben Nyström" und bekommt den Platzhalter `PERSON_7B`.
public struct Alias: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var text: String
    /// Der Buchstabe hinter der Nummer: B, C, D …
    public var suffix: String

    public init(id: UUID = UUID(), text: String, suffix: String) {
        self.id = id
        self.text = text
        self.suffix = suffix
    }
}

/// Ein Begriff mit fester Nummer. Die Nummer bleibt dem Eintrag ein Leben lang
/// erhalten und wird nach dem Löschen nicht neu vergeben.
public struct Eintrag: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    /// Die Hauptnennung, also die vollständigste Form: „Thorben Nyström".
    public var text: String
    public var kategorie: Kategorie
    public var nummer: Int
    public var aliase: [Alias]
    /// Aus einer Regel entstanden (IBAN, E-Mail …) statt von Hand gemerkt.
    public var automatischErkannt: Bool
    public var angelegt: Date

    public init(
        id: UUID = UUID(),
        text: String,
        kategorie: Kategorie,
        nummer: Int,
        aliase: [Alias] = [],
        automatischErkannt: Bool = false,
        angelegt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.kategorie = kategorie
        self.nummer = nummer
        self.aliase = aliase
        self.automatischErkannt = automatischErkannt
        self.angelegt = angelegt
    }

    public var platzhalter: String { "\(kategorie.praefix)_\(nummer)" }

    public func platzhalter(fuer alias: Alias) -> String {
        "\(kategorie.praefix)_\(nummer)\(alias.suffix)"
    }

    /// Hauptnennung und Aliase in einer Liste, längster Text zuerst. Beim
    /// Suchen im Text muss „Thorben Nyström" vor „Nyström" drankommen, sonst
    /// bleibt der Vorname stehen.
    public var alleSchreibweisen: [(text: String, platzhalter: String)] {
        var alle = [(text: text, platzhalter: platzhalter)]
        alle += aliase.map { (text: $0.text, platzhalter: platzhalter(fuer: $0)) }
        return alle.sorted { $0.text.count > $1.text.count }
    }

    /// Nächster freier Alias-Buchstabe. B, C, … Z, dann AA, AB.
    var naechsterSuffix: String {
        let belegt = Set(aliase.map(\.suffix))
        var index = 1  // 0 wäre „A" und damit die Hauptnennung selbst
        while true {
            let kandidat = Self.suffix(fuerIndex: index)
            if !belegt.contains(kandidat) { return kandidat }
            index += 1
        }
    }

    static func suffix(fuerIndex index: Int) -> String {
        let buchstaben = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var rest = index
        var ergebnis = ""
        repeat {
            ergebnis = String(buchstaben[rest % 26]) + ergebnis
            rest = rest / 26 - 1
        } while rest >= 0
        return ergebnis
    }
}

/// Der gesamte gespeicherte Zustand. `version` erlaubt späteren Programm-
/// versionen, alte Dateien zu migrieren statt sie abzulehnen.
public struct Woerterbuch: Codable, Sendable {
    public static let aktuelleVersion = 1

    public var version: Int
    public var eintraege: [Eintrag]
    /// Pro Kategorie die nächste freie Nummer, abgelegt unter `Kategorie.rawValue`.
    /// Wird beim Löschen nicht zurückgedreht.
    public var naechsteNummern: [String: Int]

    public init(
        version: Int = Woerterbuch.aktuelleVersion,
        eintraege: [Eintrag] = [],
        naechsteNummern: [String: Int] = [:]
    ) {
        self.version = version
        self.eintraege = eintraege
        self.naechsteNummern = naechsteNummern
    }

    // MARK: Anlegen und Ändern

    /// Legt einen Eintrag an und vergibt die nächste freie Nummer seiner
    /// Kategorie.
    @discardableResult
    public mutating func anlegen(
        text: String,
        kategorie: Kategorie,
        automatischErkannt: Bool = false
    ) -> Eintrag {
        let nummer = naechsteNummern[kategorie.rawValue] ?? 1
        naechsteNummern[kategorie.rawValue] = nummer + 1
        let eintrag = Eintrag(
            text: text,
            kategorie: kategorie,
            nummer: nummer,
            automatischErkannt: automatischErkannt
        )
        eintraege.append(eintrag)
        return eintrag
    }

    /// Hängt eine weitere Schreibweise an einen bestehenden Eintrag.
    @discardableResult
    public mutating func aliasHinzufuegen(_ text: String, zu eintragId: UUID) -> Alias? {
        guard let index = eintraege.firstIndex(where: { $0.id == eintragId }) else { return nil }
        if let vorhanden = eintraege[index].aliase.first(where: { $0.text == text }) {
            return vorhanden
        }
        let alias = Alias(text: text, suffix: eintraege[index].naechsterSuffix)
        eintraege[index].aliase.append(alias)
        return alias
    }

    /// Entfernt einen Eintrag samt Aliasen. Die Nummer bleibt verbrannt, damit
    /// bereits verschickte Texte eindeutig bleiben.
    public mutating func loeschen(_ eintragId: UUID) {
        eintraege.removeAll { $0.id == eintragId }
    }

    /// Leert die Sektion „automatisch erkannt".
    public mutating func automatischErkannteLoeschen() {
        eintraege.removeAll { $0.automatischErkannt }
    }

    /// Macht aus einem eigenständigen Eintrag einen Alias eines anderen. Der
    /// alte Platzhalter verschwindet damit; das ist der Preis dafür, zwei
    /// Nennungen derselben Person nachträglich zusammenzulegen.
    public mutating func zusammenlegen(_ eintragId: UUID, in zielId: UUID) {
        guard eintragId != zielId,
              let quelleIndex = eintraege.firstIndex(where: { $0.id == eintragId }),
              eintraege.contains(where: { $0.id == zielId })
        else { return }
        let quelle = eintraege[quelleIndex]
        eintraege.remove(at: quelleIndex)
        aliasHinzufuegen(quelle.text, zu: zielId)
        for alias in quelle.aliase {
            aliasHinzufuegen(alias.text, zu: zielId)
        }
    }

    // MARK: Suchen

    public func eintrag(mitId id: UUID) -> Eintrag? {
        eintraege.first { $0.id == id }
    }

    /// Findet einen Eintrag über eine seiner Schreibweisen, Groß- und
    /// Kleinschreibung egal.
    public func eintrag(fuerText text: String) -> Eintrag? {
        let gesucht = text.lowercased()
        return eintraege.first { eintrag in
            eintrag.text.lowercased() == gesucht
                || eintrag.aliase.contains { $0.text.lowercased() == gesucht }
        }
    }

    /// Löst einen Platzhalter wieder in Klartext auf. `PERSON_7` liefert die
    /// Hauptnennung, `PERSON_7B` den zugehörigen Alias.
    public func klartext(fuerPlatzhalter platzhalter: String) -> String? {
        for eintrag in eintraege {
            if eintrag.platzhalter == platzhalter { return eintrag.text }
            for alias in eintrag.aliase where eintrag.platzhalter(fuer: alias) == platzhalter {
                return alias.text
            }
        }
        return nil
    }

    /// Alle Personen, deren Hauptnennung auf denselben Nachnamen endet wie der
    /// übergebene Text. Grundlage für den Vorschlag „gehört das zu PERSON_7?".
    public func verwandtePersonen(zu text: String) -> [Eintrag] {
        guard let nachname = text.split(separator: " ").last?.lowercased(), nachname.count > 2 else {
            return []
        }
        return eintraege.filter { eintrag in
            guard eintrag.kategorie == .person else { return false }
            guard let anderer = eintrag.text.split(separator: " ").last?.lowercased() else { return false }
            return anderer == nachname
        }
    }
}
