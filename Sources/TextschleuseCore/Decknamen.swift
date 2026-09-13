import Foundation

/// Woher die Kennung hinter dem Kategoriekürzel kommt: `PERSON_3F9A1C7B2E4D6A0B5C`.
///
/// Früher war das eine laufende Nummer je Kategorie. Die verriet mehr, als
/// sie sollte: `PERSON_47` sagt, dass es mindestens 46 andere gibt, und
/// welche Person zuerst im Wörterbuch stand. Eine Zufallskennung sagt
/// nichts — aus zwei Texten lässt sich weder eine Reihenfolge noch eine
/// Anzahl ablesen.
///
/// Achtzehn Stellen aus einer UUID, Großbuchstaben und Ziffern. Das passt
/// zur Regel für selbst vergebene Decknamen und bleibt für ein Modell ein
/// einzelnes, unverwechselbares Wort.
public enum Decknamen {

    public static let kennungslaenge = 18

    /// Die Quelle der Kennungen. Bekommt die schon vergebenen Decknamen
    /// mit; der Zufall braucht sie nicht, der Zähler der Prüfungen schon.
    nonisolated(unsafe) public static var quelle: (Kategorie, Set<String>) -> String = { _, _ in zufallskennung() }

    public static func kennung(fuer kategorie: Kategorie, belegt: Set<String> = []) -> String {
        quelle(kategorie, belegt)
    }

    public static func zufallskennung() -> String {
        let roh = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        return String(roh.prefix(kennungslaenge)).uppercased()
    }

    /// Sieht eine Kennung aus wie eine von hier: achtzehn Stellen, nur
    /// Großbuchstaben A–F und Ziffern.
    public static func istZufallskennung(_ text: String) -> Bool {
        text.count == kennungslaenge
            && text.allSatisfy { $0.isHexDigit && ($0.isNumber || $0.isUppercase) }
    }

    /// Für Prüfungen: die kleinste Nummer, die in diesem Wörterbuch noch
    /// frei ist — so, wie die Nummern früher liefen. Damit lesen sich
    /// Erwartungen wie `PERSON_1` und `FIRMA_1`.
    public static func zaehleFuerPruefungen() {
        quelle = { kategorie, belegt in
            var nummer = 1
            while belegt.contains("\(kategorie.praefix)_\(nummer)") { nummer += 1 }
            return String(nummer)
        }
    }

    public static func zufallFuerAlle() {
        quelle = { _, _ in zufallskennung() }
    }
}
