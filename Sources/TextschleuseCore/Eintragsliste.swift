import Foundation

/// Bringt Wörterbucheinträge in eine Ordnung, die man mit den Augen abfahren
/// kann: erst nach Typ geclustert, innerhalb des Typs alphabetisch.
///
/// Bei dreißig Einträgen reicht eine flache Liste. Bei dreihundert nicht mehr:
/// dann sucht man eine bestimmte E-Mail-Adresse zwischen Personen und IBANs.
public enum Eintragsliste {

    /// Ein Block gleichartiger Einträge, etwa alle E-Mail-Adressen.
    public struct Gruppe: Sendable, Equatable {
        public var kategorie: Kategorie
        public var eintraege: [Eintrag]

        public init(kategorie: Kategorie, eintraege: [Eintrag]) {
            self.kategorie = kategorie
            self.eintraege = eintraege
        }
    }

    /// Sortiert und gruppiert. `suche` filtert vorher; leer heißt alles.
    ///
    /// Sortiert wird nach der Hauptnennung, nicht nach den Schreibweisen —
    /// „Herr Nyström" steht bei T wie Thorben und nicht bei H, sonst stünde
    /// derselbe Mensch an zwei Stellen der Liste.
    public static func gruppiert(_ eintraege: [Eintrag], suche: String = "") -> [Gruppe] {
        let treffer = gefiltert(eintraege, suche: suche)
        var nachKategorie: [Kategorie: [Eintrag]] = [:]
        for eintrag in treffer {
            nachKategorie[eintrag.kategorie, default: []].append(eintrag)
        }
        // Die Reihenfolge der Blöcke folgt der Deklaration in `Kategorie`:
        // Person, Firma, Ort zuerst, weil dort die meisten Zuordnungen
        // passieren. Alphabetisch wären die Blöcke jedes Mal woanders.
        return Kategorie.allCases.compactMap { kategorie in
            guard let gefunden = nachKategorie[kategorie], !gefunden.isEmpty else { return nil }
            return Gruppe(kategorie: kategorie, eintraege: gefunden.sorted(by: vorne))
        }
    }

    /// Alphabetisch, ohne Rücksicht auf Groß- und Kleinschreibung oder
    /// Umlautpünktchen. Bei Gleichstand entscheidet die Kennung, damit die
    /// Reihenfolge stabil bleibt.
    public static func vorne(_ links: Eintrag, _ rechts: Eintrag) -> Bool {
        let vergleich = links.text.compare(
            rechts.text,
            options: [.caseInsensitive, .diacriticInsensitive, .numeric],
            range: nil,
            locale: Locale(identifier: "de_DE")
        )
        if vergleich != .orderedSame { return vergleich == .orderedAscending }
        return links.kennung < rechts.kennung
    }

    /// Sucht in Hauptnennung, Schreibweisen und Deckname. Ein Eintrag, dessen
    /// Alias passt, bleibt trotzdem unter seinem eigenen Anfangsbuchstaben.
    public static func gefiltert(_ eintraege: [Eintrag], suche: String) -> [Eintrag] {
        let begriff = suche.trimmingCharacters(in: .whitespaces)
        guard !begriff.isEmpty else { return eintraege }
        return eintraege.filter { eintrag in
            var felder = [eintrag.text, eintrag.platzhalter, eintrag.kategorie.anzeigename]
            felder.append(contentsOf: eintrag.aliase.map(\.text))
            felder.append(contentsOf: eintrag.aliase.map { eintrag.platzhalter + $0.suffix })
            return felder.contains { enthaelt($0, begriff) }
        }
    }

    private static func enthaelt(_ heuhaufen: String, _ nadel: String) -> Bool {
        heuhaufen.range(
            of: nadel,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }
}
