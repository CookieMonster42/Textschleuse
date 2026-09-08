import Foundation
import TextschleuseCore

/// Was diese Sitzung über bearbeitete Texte weiß.
///
/// Absichtlich flüchtig: nichts davon liegt auf der Platte. Dauerhaft
/// gespeichert wird allein das Wörterbuch. Beim Beenden ist der Verlauf weg,
/// und damit auch jede Zuordnung von `UNBEKANNT_3` zu einem echten Namen.
///
/// Der Verlauf hängt an der App, nicht an einem Fenster. Nur so sieht das
/// Hauptfenster, was gerade im Popup passiert ist, und umgekehrt.
final class Sitzung {

    /// So viele Texte werden zurückbehalten. Mehr sind selten hilfreich, und
    /// jeder Text hält die echten Namen im Arbeitsspeicher.
    static let hoechstzahl = 20

    struct Vorgang: Identifiable {
        let id: UUID
        var analyse: Analyse
        var zeitpunkt: Date

        /// Der Anfang des Textes, für die Liste im Fenster.
        var vorschau: String {
            let eineZeile = analyse.original
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !eineZeile.isEmpty else { return "(leer)" }
            return eineZeile.count > 60 ? String(eineZeile.prefix(60)) + " …" : eineZeile
        }
    }

    private(set) var vorgaenge: [Vorgang] = []

    /// Alle Sitzungsplatzhalter, die je vergeben wurden — nicht nur die des
    /// letzten Textes. Sonst ließe sich die Antwort auf die vorletzte Mail
    /// nicht mehr zurückdrehen, sobald man die nächste geschützt hat.
    private(set) var unbekannte: [String: String] = [:]

    var neuester: Vorgang? { vorgaenge.first }

    /// Legt einen neuen Vorgang an und gibt seine Kennung zurück.
    @discardableResult
    func beginne(_ analyse: Analyse, jetzt: Date = Date()) -> UUID {
        let vorgang = Vorgang(id: UUID(), analyse: analyse, zeitpunkt: jetzt)
        vorgaenge.insert(vorgang, at: 0)
        if vorgaenge.count > Self.hoechstzahl {
            vorgaenge.removeLast(vorgaenge.count - Self.hoechstzahl)
        }
        uebernimmUnbekannte(analyse)
        return vorgang.id
    }

    /// Schreibt einen laufenden Vorgang fort und holt ihn nach vorn.
    func aktualisiere(_ kennung: UUID, mit analyse: Analyse, jetzt: Date = Date()) {
        guard let index = vorgaenge.firstIndex(where: { $0.id == kennung }) else { return }
        vorgaenge[index].analyse = analyse
        vorgaenge[index].zeitpunkt = jetzt
        if index != 0 {
            let vorgang = vorgaenge.remove(at: index)
            vorgaenge.insert(vorgang, at: 0)
        }
        uebernimmUnbekannte(analyse)
    }

    func vorgang(_ kennung: UUID) -> Vorgang? {
        vorgaenge.first { $0.id == kennung }
    }

    func leere() {
        vorgaenge.removeAll()
        unbekannte.removeAll()
    }

    /// Sammelt die Sitzungsplatzhalter ein, statt sie zu ersetzen.
    private func uebernimmUnbekannte(_ analyse: Analyse) {
        for (platzhalter, klartext) in analyse.unbekannte {
            unbekannte[platzhalter] = klartext
        }
    }
}
