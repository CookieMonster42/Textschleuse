import Foundation

/// Wörter, die nie als Vermutung durchgehen.
///
/// „August" ist ein Monat und ein Vorname, „Mai" ebenso. Die Heuristik sieht
/// ein großgeschriebenes Wort und hält es für eine Person; wer über Termine
/// schreibt, verwirft dann in jedem zweiten Text dieselben Wörter.
///
/// Die Liste bremst ausschließlich Vermutungen. Was eine Regel findet, geht
/// durch — „geboren am 3. August 1979" bleibt ein Geburtsdatum, weil die
/// Datumsregel den ganzen Ausdruck greift und nicht das einzelne Wort. Auch
/// ein Wörterbucheintrag schlägt die Liste: wenn du „Mai" einmal ausdrücklich
/// als Person gemerkt hast, weißt du es besser.
public enum Freiliste {

    /// Eingebaut und nicht abwählbar. Monate und Wochentage stehen in fast
    /// jedem Geschäftstext und meinen dort nie einen Menschen.
    public static let eingebaut: [String] = [
        "Januar", "Februar", "März", "April", "Mai", "Juni",
        "Juli", "August", "September", "Oktober", "November", "Dezember",
        "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag",
        "Sonnabend", "Sonntag",
    ]

    /// Vergleicht ohne Rücksicht auf Groß- und Kleinschreibung und auf
    /// Umlautpünktchen: „maerz" trifft „März".
    public static func gleich(_ links: String, _ rechts: String) -> Bool {
        links.compare(
            rechts,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: nil,
            locale: Locale(identifier: "de_DE")
        ) == .orderedSame
    }

    /// Steht das Wort auf der Liste? Gebeugte Formen und Umlautumschriften
    /// zählen mit, damit „Augusts" und „Maerz" nicht durchrutschen — dafür
    /// dasselbe Musterwerk wie bei den Wörterbucheinträgen.
    public static func istFrei(_ wort: String, eigene: [String] = []) -> Bool {
        let geputzt = wort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !geputzt.isEmpty else { return false }
        let alle = eingebaut + eigene
        if alle.contains(where: { gleich($0, geputzt) }) { return true }
        return alle.contains { kandidat in
            guard let regex = Varianten.regex(fuer: kandidat) else { return false }
            let bereich = NSRange(location: 0, length: (geputzt as NSString).length)
            // Nur ein Treffer, der das ganze Wort abdeckt, zählt. Sonst wäre
            // „Maike" frei, weil „Mai" darin steckt.
            guard let treffer = regex.firstMatch(in: geputzt, range: bereich) else { return false }
            return treffer.range == bereich
        }
    }

    /// Die vollständige Liste für die Oberfläche, alphabetisch, mit der
    /// Angabe, ob sich der Eintrag entfernen lässt.
    public static func alle(eigene: [String]) -> [(wort: String, eingebaut: Bool)] {
        let fest = eingebaut.map { (wort: $0, eingebaut: true) }
        let selbst = eigene.map { (wort: $0, eingebaut: false) }
        return (fest + selbst).sorted {
            $0.wort.localizedStandardCompare($1.wort) == .orderedAscending
        }
    }
}
