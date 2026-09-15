import CryptoKit
import Foundation

/// Woher die Kennung hinter dem Kategoriekürzel kommt: `PERSON_3F9A1C7B2E4D6A0B5C`.
///
/// Sie wird aus dem Seed des Wörterbuchs und dem Wortlaut abgeleitet
/// (HMAC-SHA256, achtzehn Stellen). Das heißt: gleicher Seed, gleicher
/// Name, gleiche Kennung — auf jedem Rechner und auch nach dem Löschen und
/// Neuanlegen. Wer den Seed hat und den Namen kennt, weiß, welcher
/// Deckname dazugehört, und kann einen Text zurückdrehen, sobald der Name
/// in seinem Wörterbuch steht. Wer den Seed nicht hat, sieht nur Zufall:
/// aus zwei Texten lässt sich weder eine Reihenfolge noch eine Anzahl
/// ablesen, und aus der Kennung nicht der Name.
///
/// Der Seed ist damit ein Geheimnis wie ein Passwort. Er liegt im
/// verschlüsselten Wörterbuch und wandert mit dem Klartext-Export.
public enum Decknamen {

    public static let kennungslaenge = 18

    public struct Anfrage {
        public var text: String
        public var kategorie: Kategorie
        public var seed: String
        /// Schon vergebene Decknamen. Die Ableitung weicht nur aus, wenn
        /// der ihre zufällig belegt ist.
        public var belegt: Set<String>
    }

    /// Die Quelle der Kennungen. Im Regelfall die Ableitung; die Prüfungen
    /// hängen hier einen Zähler ein, damit Erwartungen wie `PERSON_1`
    /// lesbar bleiben.
    nonisolated(unsafe) public static var quelle: (Anfrage) -> String = abgeleitet

    public static func kennung(
        fuer text: String,
        kategorie: Kategorie,
        seed: String,
        belegt: Set<String> = []
    ) -> String {
        quelle(Anfrage(text: text, kategorie: kategorie, seed: seed, belegt: belegt))
    }

    /// Der Regelfall: aus Seed und Wortlaut abgeleitet. Ist der Deckname
    /// ausgerechnet belegt, kommt eine Laufnummer in die Ableitung.
    public static func abgeleitet(_ anfrage: Anfrage) -> String {
        var versuch = 0
        while true {
            let kennung = ableiten(text: anfrage.text, seed: anfrage.seed, versuch: versuch)
            if !anfrage.belegt.contains("\(anfrage.kategorie.praefix)_\(kennung)") { return kennung }
            versuch += 1
        }
    }

    /// Die reine Rechnung, ohne Rücksicht auf Belegtes.
    public static func ableiten(text: String, seed: String, versuch: Int = 0) -> String {
        let schluessel = SymmetricKey(data: Data(seed.utf8))
        var nachricht = Data(schluesselwort(text).utf8)
        if versuch > 0 { nachricht.append(Data("#\(versuch)".utf8)) }
        let mac = HMAC<SHA256>.authenticationCode(for: nachricht, using: schluessel)
        let hex = mac.map { String(format: "%02X", $0) }.joined()
        return String(hex.prefix(kennungslaenge))
    }

    /// Wie ein Wortlaut in die Rechnung eingeht: klein, ohne Rand, ein
    /// Leerzeichen zwischen den Wörtern. „Thorben  Nyström" und „thorben
    /// nyström" sind derselbe Name.
    public static func schluesselwort(_ text: String) -> String {
        text.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Ein frischer Seed: 32 Stellen aus zwei UUIDs.
    public static func neuerSeed() -> String {
        let roh = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "")
        return String(roh.prefix(32)).uppercased()
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
        quelle = { anfrage in
            var nummer = 1
            while anfrage.belegt.contains("\(anfrage.kategorie.praefix)_\(nummer)") { nummer += 1 }
            return String(nummer)
        }
    }

    /// Zurück zum Regelfall.
    public static func ableitenFuerAlle() {
        quelle = abgeleitet
    }
}
