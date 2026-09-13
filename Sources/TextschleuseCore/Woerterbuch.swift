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

    /// Selbst vergebener Deckname, etwa `KUNDE_NORD` statt `FIRMA_3`. Ist er
    /// gesetzt, gilt er überall statt der automatischen Nummer.
    public var eigenerDeckname: String?

    /// Alle Decknamen, unter denen dieser Eintrag schon einmal im Umlauf war.
    /// Sie bleiben auflösbar, sonst ließe sich eine Antwort auf eine ältere
    /// Mail nach dem Umbenennen nicht mehr zurückdrehen.
    public var fruehereDecknamen: [String]

    public init(
        id: UUID = UUID(),
        text: String,
        kategorie: Kategorie,
        nummer: Int,
        aliase: [Alias] = [],
        automatischErkannt: Bool = false,
        angelegt: Date = Date(),
        eigenerDeckname: String? = nil,
        fruehereDecknamen: [String] = []
    ) {
        self.id = id
        self.text = text
        self.kategorie = kategorie
        self.nummer = nummer
        self.aliase = aliase
        self.automatischErkannt = automatischErkannt
        self.angelegt = angelegt
        self.eigenerDeckname = eigenerDeckname
        self.fruehereDecknamen = fruehereDecknamen
    }

    /// Von Hand geschrieben statt automatisch abgeleitet: die beiden neuen
    /// Felder fehlen in Dateien der Version 1, und der abgeleitete Decoder
    /// bricht bei fehlenden Schlüsseln ab, auch wenn ein Vorgabewert dasteht.
    public init(from decoder: Decoder) throws {
        let behaelter = try decoder.container(keyedBy: CodingKeys.self)
        id = try behaelter.decode(UUID.self, forKey: .id)
        text = try behaelter.decode(String.self, forKey: .text)
        kategorie = try behaelter.decode(Kategorie.self, forKey: .kategorie)
        nummer = try behaelter.decode(Int.self, forKey: .nummer)
        aliase = try behaelter.decodeIfPresent([Alias].self, forKey: .aliase) ?? []
        automatischErkannt = try behaelter.decodeIfPresent(Bool.self, forKey: .automatischErkannt) ?? false
        angelegt = try behaelter.decodeIfPresent(Date.self, forKey: .angelegt) ?? Date()
        eigenerDeckname = try behaelter.decodeIfPresent(String.self, forKey: .eigenerDeckname)
        fruehereDecknamen = try behaelter.decodeIfPresent([String].self, forKey: .fruehereDecknamen) ?? []
    }

    /// Der automatisch vergebene Name. Bleibt auch nach dem Umbenennen
    /// erhalten, damit die Nummer nicht neu vergeben wird.
    public var standardDeckname: String { "\(kategorie.praefix)_\(nummer)" }

    public var platzhalter: String { eigenerDeckname ?? standardDeckname }

    public func platzhalter(fuer alias: Alias) -> String {
        "\(platzhalter)\(alias.suffix)"
    }

    /// Jeder Name, unter dem dieser Eintrag in einem Text stehen kann:
    /// aktueller Deckname, frühere Decknamen, beides je Alias.
    public var alleDecknamen: [String] {
        var namen = [platzhalter] + fruehereDecknamen
        for name in namen { namen += aliase.map { "\(name)\($0.suffix)" } }
        return Array(Set(namen))
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
    /// Wörter, die nie als Vermutung durchgehen. Siehe `Freiliste`.
    public var eigeneFreieWoerter: [String]

    public init(
        version: Int = Woerterbuch.aktuelleVersion,
        eintraege: [Eintrag] = [],
        naechsteNummern: [String: Int] = [:],
        eigeneFreieWoerter: [String] = []
    ) {
        self.version = version
        self.eintraege = eintraege
        self.naechsteNummern = naechsteNummern
        self.eigeneFreieWoerter = eigeneFreieWoerter
    }

    /// Von Hand geschrieben: `eigeneFreieWoerter` fehlt in älteren Dateien,
    /// und der abgeleitete Decoder bricht bei fehlenden Schlüsseln ab.
    public init(from decoder: Decoder) throws {
        let behaelter = try decoder.container(keyedBy: CodingKeys.self)
        version = try behaelter.decode(Int.self, forKey: .version)
        eintraege = try behaelter.decode([Eintrag].self, forKey: .eintraege)
        naechsteNummern = try behaelter.decodeIfPresent(
            [String: Int].self,
            forKey: .naechsteNummern
        ) ?? [:]
        eigeneFreieWoerter = try behaelter.decodeIfPresent(
            [String].self,
            forKey: .eigeneFreieWoerter
        ) ?? []
    }

    // MARK: Freiliste

    /// Steht das Wort auf der Freiliste — eingebaut oder selbst ergänzt?
    public func istFrei(_ wort: String) -> Bool {
        Freiliste.istFrei(wort, eigene: eigeneFreieWoerter)
    }

    /// Nimmt ein Wort auf. Liefert `false`, wenn es schon draufstand.
    @discardableResult
    public mutating func gibFrei(_ wort: String) -> Bool {
        let geputzt = wort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !geputzt.isEmpty, !istFrei(geputzt) else { return false }
        eigeneFreieWoerter.append(geputzt)
        return true
    }

    /// Nimmt ein selbst ergänztes Wort wieder herunter. Die eingebauten
    /// bleiben, die stehen nicht zur Wahl.
    @discardableResult
    public mutating func nimmVonFreiliste(_ wort: String) -> Bool {
        let vorher = eigeneFreieWoerter.count
        eigeneFreieWoerter.removeAll { Freiliste.gleich($0, wort) }
        return eigeneFreieWoerter.count != vorher
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

    // MARK: Bearbeiten

    public enum EintragFehler: LocalizedError, Equatable {
        case leer
        case schonVorhanden(String)

        public var errorDescription: String? {
            switch self {
            case .leer:
                return "Der Begriff darf nicht leer sein."
            case .schonVorhanden(let text):
                return "„\(text)\" steht schon in einem anderen Eintrag."
            }
        }
    }

    /// Ändert die Hauptnennung. Der Deckname bleibt, wie er ist — sonst
    /// stimmten die schon verschickten Texte nicht mehr.
    public mutating func aendereText(_ eintragId: UUID, auf eingabe: String) throws {
        let text = eingabe.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw EintragFehler.leer }
        guard let index = eintraege.firstIndex(where: { $0.id == eintragId }) else { return }
        try pruefeFreienBegriff(text, ausser: eintragId)
        eintraege[index].text = text
    }

    /// Ändert die Kategorie. Hängt der Deckname an ihr — `PERSON_3` —, dann
    /// ändert er sich mit; der alte bleibt auflösbar. Ein selbst vergebener
    /// Deckname bleibt unangetastet.
    public mutating func aendereKategorie(_ eintragId: UUID, auf kategorie: Kategorie) {
        guard let index = eintraege.firstIndex(where: { $0.id == eintragId }),
              eintraege[index].kategorie != kategorie
        else { return }

        let bisher = eintraege[index].platzhalter
        // Eine frische Nummer aus der neuen Kategorie, sonst kollidiert sie
        // mit einem Eintrag, der dieselbe Nummer dort schon hat.
        let nummer = naechsteNummern[kategorie.rawValue] ?? 1
        naechsteNummern[kategorie.rawValue] = nummer + 1

        eintraege[index].kategorie = kategorie
        eintraege[index].nummer = nummer

        if eintraege[index].platzhalter != bisher,
           !eintraege[index].fruehereDecknamen.contains(bisher) {
            eintraege[index].fruehereDecknamen.append(bisher)
        }
    }

    /// Ändert die Schreibweise eines Alias. Sein Buchstabe bleibt, damit
    /// `PERSON_3B` weiter dasselbe meint.
    public mutating func aendereAlias(_ aliasId: UUID, in eintragId: UUID, auf eingabe: String) throws {
        let text = eingabe.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw EintragFehler.leer }
        guard let index = eintraege.firstIndex(where: { $0.id == eintragId }),
              let aliasIndex = eintraege[index].aliase.firstIndex(where: { $0.id == aliasId })
        else { return }
        try pruefeFreienBegriff(text, ausser: eintragId)
        eintraege[index].aliase[aliasIndex].text = text
    }

    /// Entfernt eine Schreibweise. Ihr Buchstabe wird nicht neu vergeben.
    public mutating func loescheAlias(_ aliasId: UUID, in eintragId: UUID) {
        guard let index = eintraege.firstIndex(where: { $0.id == eintragId }) else { return }
        eintraege[index].aliase.removeAll { $0.id == aliasId }
    }

    /// Macht aus einer Schreibweise die Hauptnennung und umgekehrt. Für den
    /// Fall, dass zuerst „Nyström" gemerkt wurde und später der volle Name
    /// auftaucht.
    public mutating func machtZurHauptnennung(_ aliasId: UUID, in eintragId: UUID) {
        guard let index = eintraege.firstIndex(where: { $0.id == eintragId }),
              let aliasIndex = eintraege[index].aliase.firstIndex(where: { $0.id == aliasId })
        else { return }
        let bisherigeHauptnennung = eintraege[index].text
        eintraege[index].text = eintraege[index].aliase[aliasIndex].text
        eintraege[index].aliase[aliasIndex].text = bisherigeHauptnennung
    }

    private func pruefeFreienBegriff(_ text: String, ausser eintragId: UUID) throws {
        let gesucht = text.lowercased()
        let belegt = eintraege
            .filter { $0.id != eintragId }
            .contains { eintrag in
                eintrag.text.lowercased() == gesucht
                    || eintrag.aliase.contains { $0.text.lowercased() == gesucht }
            }
        if belegt { throw EintragFehler.schonVorhanden(text) }
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
    /// Hauptnennung, `PERSON_7B` den zugehörigen Alias. Frühere Decknamen
    /// zählen mit, damit Antworten auf ältere Texte weiter aufgehen.
    public func klartext(fuerPlatzhalter platzhalter: String) -> String? {
        let gesucht = platzhalter.uppercased()
        for eintrag in eintraege {
            for name in [eintrag.platzhalter] + eintrag.fruehereDecknamen {
                if name.uppercased() == gesucht { return eintrag.text }
                for alias in eintrag.aliase where "\(name)\(alias.suffix)".uppercased() == gesucht {
                    return alias.text
                }
            }
        }
        return nil
    }

    /// Alle Decknamen, die irgendwo im Wörterbuch vergeben sind. Grundlage für
    /// die Suche im Rückweg und für die Kollisionsprüfung beim Umbenennen.
    public var alleDecknamen: Set<String> {
        Set(eintraege.flatMap(\.alleDecknamen))
    }

    /// Was hinter einem Decknamen steckt, mit der Herkunft dazu.
    public struct Aufloesung: Sendable {
        public var eintrag: Eintrag
        /// Der Klartext: die Hauptnennung oder die Schreibweise.
        public var klartext: String
        /// Gesetzt, wenn der Deckname zu einer Schreibweise gehört.
        public var alias: Alias?
        /// Der Eintrag heißt inzwischen anders; dieser Name ist von früher.
        public var istFrueherer: Bool
    }

    /// Schlägt einen Decknamen nach. Anders als `klartext(fuerPlatzhalter:)`
    /// sagt das hier auch, zu welchem Eintrag er gehört und ob er noch aktuell
    /// ist — für die Frage „wer war nochmal PERSON_3?".
    ///
    /// Schreibweisen und frühere Namen zählen mit. Auch Leerzeichen und
    /// Bindestriche statt Unterstrich werden verstanden, weil Modelle
    /// `PERSON 3` schreiben.
    public func aufloesen(_ eingabe: String) -> Aufloesung? {
        let gesucht = eingabe
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
        guard !gesucht.isEmpty else { return nil }

        for eintrag in eintraege {
            let aktuell = eintrag.platzhalter.uppercased()
            for name in [eintrag.platzhalter] + eintrag.fruehereDecknamen {
                let istFrueherer = name.uppercased() != aktuell
                if name.uppercased() == gesucht {
                    return Aufloesung(
                        eintrag: eintrag,
                        klartext: eintrag.text,
                        alias: nil,
                        istFrueherer: istFrueherer
                    )
                }
                for alias in eintrag.aliase where "\(name)\(alias.suffix)".uppercased() == gesucht {
                    return Aufloesung(
                        eintrag: eintrag,
                        klartext: alias.text,
                        alias: alias,
                        istFrueherer: istFrueherer
                    )
                }
            }
        }
        return nil
    }

    // MARK: Umbenennen

    public enum DecknamenFehler: LocalizedError, Equatable {
        case leer
        case ungueltigeZeichen
        case zuLang(Int)
        case ohneBuchstabe
        case vergeben(String)

        public var errorDescription: String? {
            switch self {
            case .leer:
                return "Der Deckname darf nicht leer sein."
            case .ungueltigeZeichen:
                return "Erlaubt sind Großbuchstaben, Ziffern und Unterstrich. "
                    + "Leerzeichen und Umlaute nicht — sonst findet der Rückweg den Namen in der "
                    + "KI-Antwort nicht mehr sicher wieder."
            case .zuLang(let hoechstens):
                return "Höchstens \(hoechstens) Zeichen."
            case .ohneBuchstabe:
                return "Mindestens ein Buchstabe muss dabei sein."
            case .vergeben(let name):
                return "\(name) ist schon vergeben."
            }
        }
    }

    static let hoechstlaengeDeckname = 40

    /// Prüft einen Decknamen und liefert ihn in der Form, in der er gespeichert
    /// wird. `eigenerId` bleibt bei der Kollisionsprüfung außen vor, sonst
    /// stößt sich ein Eintrag an sich selbst.
    public func pruefeDeckname(_ eingabe: String, fuer eigenerId: UUID?) throws -> String {
        let name = eingabe.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !name.isEmpty else { throw DecknamenFehler.leer }
        guard name.count <= Self.hoechstlaengeDeckname else {
            throw DecknamenFehler.zuLang(Self.hoechstlaengeDeckname)
        }
        guard name.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber || $0 == "_") }) else {
            throw DecknamenFehler.ungueltigeZeichen
        }
        guard name.contains(where: \.isLetter) else { throw DecknamenFehler.ohneBuchstabe }

        let fremde = eintraege
            .filter { $0.id != eigenerId }
            .flatMap(\.alleDecknamen)
            .map { $0.uppercased() }
        guard !fremde.contains(name) else { throw DecknamenFehler.vergeben(name) }
        return name
    }

    /// Gibt einem Eintrag einen neuen Decknamen. Der bisherige bleibt als
    /// früherer Name auflösbar.
    @discardableResult
    public mutating func umbenennen(_ eintragId: UUID, auf eingabe: String) throws -> String {
        let name = try pruefeDeckname(eingabe, fuer: eintragId)
        guard let index = eintraege.firstIndex(where: { $0.id == eintragId }) else { return name }

        let bisher = eintraege[index].platzhalter
        guard bisher != name else { return name }
        if !eintraege[index].fruehereDecknamen.contains(bisher) {
            eintraege[index].fruehereDecknamen.append(bisher)
        }
        eintraege[index].eigenerDeckname = name
        return name
    }

    /// Hängt einen Decknamen an einen bestehenden Eintrag, ohne dessen
    /// aktuellen Namen zu ändern.
    ///
    /// Der Fall kommt vom Rückweg: in einer KI-Antwort steht `UNBEKANNT_3`
    /// oder `PERSON_9` aus einer Sitzung, die es nicht mehr gibt. Wer weiß,
    /// wer gemeint war, sagt es hier einmal — danach löst der Name dauerhaft
    /// auf, auch in jeder späteren Antwort.
    @discardableResult
    public mutating func ordneDecknameZu(_ eingabe: String, zu eintragId: UUID) throws -> String {
        let name = try pruefeDeckname(eingabe, fuer: eintragId)
        guard let index = eintraege.firstIndex(where: { $0.id == eintragId }) else { return name }
        guard eintraege[index].platzhalter.uppercased() != name else { return name }
        if !eintraege[index].fruehereDecknamen.contains(where: { $0.uppercased() == name }) {
            eintraege[index].fruehereDecknamen.append(name)
        }
        return name
    }

    /// Legt einen Eintrag an, der von Anfang an einen bestimmten Decknamen
    /// trägt. Für den Rückweg: `UNBEKANNT_3` war „Thorben Nyström", und das
    /// soll ab jetzt so bleiben.
    @discardableResult
    public mutating func anlegen(
        text: String,
        kategorie: Kategorie,
        deckname eingabe: String
    ) throws -> Eintrag {
        let sauber = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sauber.isEmpty else { throw EintragFehler.leer }
        let name = try pruefeDeckname(eingabe, fuer: nil)
        try pruefeFreienBegriff(sauber, ausser: UUID())

        var eintrag = anlegen(text: sauber, kategorie: kategorie)
        eintrag.eigenerDeckname = name
        if let index = eintraege.firstIndex(where: { $0.id == eintrag.id }) {
            eintraege[index] = eintrag
        }
        return eintrag
    }

    /// Nimmt den eigenen Decknamen zurück. Der Eintrag heißt danach wieder
    /// `PERSON_7`.
    public mutating func decknameZuruecksetzen(_ eintragId: UUID) {
        guard let index = eintraege.firstIndex(where: { $0.id == eintragId }),
              let bisher = eintraege[index].eigenerDeckname
        else { return }
        if !eintraege[index].fruehereDecknamen.contains(bisher) {
            eintraege[index].fruehereDecknamen.append(bisher)
        }
        eintraege[index].eigenerDeckname = nil
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
