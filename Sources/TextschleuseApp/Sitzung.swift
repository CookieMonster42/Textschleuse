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
        var vorschau: String { Sitzung.vorschau(analyse.original) }
    }

    /// Ein Text, der zurückgedreht wurde. Eigener Verlauf, weil es ein
    /// anderer Text ist: die Antwort, nicht die Anfrage.
    struct RueckwegVorgang: Identifiable {
        let id: UUID
        var text: String
        var zeitpunkt: Date

        var vorschau: String { Sitzung.vorschau(text) }
    }

    static func vorschau(_ text: String) -> String {
        let eineZeile = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !eineZeile.isEmpty else { return "(leer)" }
        return eineZeile.count > 60 ? String(eineZeile.prefix(60)) + " …" : eineZeile
    }

    private(set) var vorgaenge: [Vorgang] = []
    private(set) var rueckwegVorgaenge: [RueckwegVorgang] = []

    /// Alle Sitzungsplatzhalter, die je vergeben wurden — nicht nur die des
    /// letzten Textes. Sonst ließe sich die Antwort auf die vorletzte Mail
    /// nicht mehr zurückdrehen, sobald man die nächste geschützt hat.
    private(set) var unbekannte: [String: String] = [:]

    var neuester: Vorgang? { vorgaenge.first }
    var neuesterRueckweg: RueckwegVorgang? { rueckwegVorgaenge.first }

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

    // MARK: Rückweg

    @discardableResult
    func beginneRueckweg(_ text: String, jetzt: Date = Date()) -> UUID {
        let vorgang = RueckwegVorgang(id: UUID(), text: text, zeitpunkt: jetzt)
        rueckwegVorgaenge.insert(vorgang, at: 0)
        if rueckwegVorgaenge.count > Self.hoechstzahl {
            rueckwegVorgaenge.removeLast(rueckwegVorgaenge.count - Self.hoechstzahl)
        }
        return vorgang.id
    }

    func aktualisiereRueckweg(_ kennung: UUID, mit text: String, jetzt: Date = Date()) {
        guard let index = rueckwegVorgaenge.firstIndex(where: { $0.id == kennung }) else { return }
        rueckwegVorgaenge[index].text = text
        rueckwegVorgaenge[index].zeitpunkt = jetzt
        if index != 0 {
            let vorgang = rueckwegVorgaenge.remove(at: index)
            rueckwegVorgaenge.insert(vorgang, at: 0)
        }
    }

    func rueckwegVorgang(_ kennung: UUID) -> RueckwegVorgang? {
        rueckwegVorgaenge.first { $0.id == kennung }
    }

    func leere() {
        vorgaenge.removeAll()
        rueckwegVorgaenge.removeAll()
        unbekannte.removeAll()
    }

    /// Sammelt die Sitzungsplatzhalter ein, statt sie zu ersetzen.
    private func uebernimmUnbekannte(_ analyse: Analyse) {
        for (platzhalter, klartext) in analyse.unbekannte {
            unbekannte[platzhalter] = klartext
        }
    }
}
