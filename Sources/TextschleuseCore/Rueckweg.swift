import Foundation

/// Ein Platzhalter, den der Rückweg im Text gefunden hat.
public struct PlatzhalterFund: Identifiable, Sendable {
    public let id: UUID
    public var bereich: NSRange
    /// So wie er im Text steht, etwa `Person_7b`.
    public var geschrieben: String
    /// Normalisiert, etwa `PERSON_7B`.
    public var normal: String
    /// Der Klartext, falls auflösbar.
    public var klartext: String?

    public init(
        id: UUID = UUID(),
        bereich: NSRange,
        geschrieben: String,
        normal: String,
        klartext: String?
    ) {
        self.id = id
        self.bereich = bereich
        self.geschrieben = geschrieben
        self.normal = normal
        self.klartext = klartext
    }

    public var istAufloesbar: Bool { klartext != nil }
}

public struct RueckwegErgebnis: Sendable {
    public var original: String
    public var funde: [PlatzhalterFund]

    public init(original: String, funde: [PlatzhalterFund]) {
        self.original = original
        self.funde = funde
    }

    public var aufgeloest: [PlatzhalterFund] { funde.filter(\.istAufloesbar) }
    public var offen: [PlatzhalterFund] { funde.filter { !$0.istAufloesbar } }

    /// Der zurückgedrehte Text. Platzhalter ohne Zuordnung bleiben stehen.
    public var ergebnis: String {
        let text = NSMutableString(string: original)
        for fund in funde.sorted(by: { $0.bereich.location > $1.bereich.location }) {
            guard let klartext = fund.klartext else { continue }
            text.replaceCharacters(in: fund.bereich, with: klartext)
        }
        return text as String
    }
}

/// Dreht Platzhalter wieder in Klartext.
///
/// Modelle formatieren Platzhalter gern um. `**PERSON_1**`, `<PERSON_1>`,
/// `PERSON 1` und `Person_1` meinen alle dasselbe und werden alle erkannt. Die
/// Auszeichnung drumherum bleibt stehen, ersetzt wird nur der Kern.
public enum Rueckweg {

    /// Das Muster für automatisch vergebene Namen: Kategoriekürzel, Nummer,
    /// optional ein Aliasbuchstabe.
    static var muster: String {
        let praefixe = Kategorie.allCases
            .map { NSRegularExpression.escapedPattern(for: $0.praefix) }
            .sorted { $0.count > $1.count }
            .joined(separator: "|")
        return "(?<![\\p{L}\\p{N}])(\(praefixe))[ _\\-]?(\\d+)([A-Za-z]{0,3})(?![\\p{L}\\p{N}])"
    }

    /// Das Muster für selbst vergebene Decknamen. Die lassen sich nicht aus
    /// einer Kategorie ableiten, deshalb wird jeder bekannte Name einzeln
    /// gesucht. Zwischen den Wortteilen darf statt des Unterstrichs auch ein
    /// Leerzeichen oder Bindestrich stehen — Modelle schreiben `KUNDE NORD`.
    static func musterFuerEigene(_ namen: [String]) -> String? {
        let brauchbare = namen
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
        guard !brauchbare.isEmpty else { return nil }

        let teile = brauchbare.map { name in
            name.split(separator: "_", omittingEmptySubsequences: true)
                .map { NSRegularExpression.escapedPattern(for: String($0)) }
                .joined(separator: "[ _\\-]?")
        }
        return "(?<![\\p{L}\\p{N}])(?:\(teile.joined(separator: "|")))(?![\\p{L}\\p{N}])"
    }

    public static func analysiere(
        _ text: String,
        woerterbuch: Woerterbuch,
        unbekannte: [String: String] = [:]
    ) -> RueckwegErgebnis {
        let nsText = text as NSString
        var funde: [PlatzhalterFund] = []

        for treffer in RegexWerkzeug.treffer(muster, in: nsText, optionen: [.caseInsensitive]) {
            let praefix = nsText.substring(with: treffer.range(at: 1)).uppercased()
            let nummer = nsText.substring(with: treffer.range(at: 2))
            let suffixBereich = treffer.range(at: 3)
            let suffix = suffixBereich.location == NSNotFound || suffixBereich.length == 0
                ? ""
                : nsText.substring(with: suffixBereich).uppercased()

            let normal = "\(praefix)_\(nummer)\(suffix)"
            funde.append(PlatzhalterFund(
                bereich: treffer.range,
                geschrieben: nsText.substring(with: treffer.range),
                normal: normal,
                klartext: woerterbuch.klartext(fuerPlatzhalter: normal) ?? unbekannte[normal]
            ))
        }

        // Selbst vergebene Namen zusätzlich suchen. Was das Kategoriemuster
        // schon erwischt hat, fällt hinterher über die Überschneidung raus.
        let eigene = woerterbuch.alleDecknamen.filter { name in
            RegexWerkzeug.treffer(muster, in: name as NSString).isEmpty
        }
        if let eigenesMuster = musterFuerEigene(Array(eigene)) {
            for treffer in RegexWerkzeug.treffer(eigenesMuster, in: nsText, optionen: [.caseInsensitive]) {
                let geschrieben = nsText.substring(with: treffer.range)
                let normal = geschrieben
                    .uppercased()
                    .replacingOccurrences(of: " ", with: "_")
                    .replacingOccurrences(of: "-", with: "_")
                funde.append(PlatzhalterFund(
                    bereich: treffer.range,
                    geschrieben: geschrieben,
                    normal: normal,
                    klartext: woerterbuch.klartext(fuerPlatzhalter: normal) ?? unbekannte[normal]
                ))
            }
        }

        return RueckwegErgebnis(original: text, funde: ohneUeberschneidungen(funde))
    }

    /// Bei gleicher Stelle gewinnt der längere Treffer. `KUNDE_NORD_2` schlägt
    /// eine Teilübereinstimmung.
    private static func ohneUeberschneidungen(_ funde: [PlatzhalterFund]) -> [PlatzhalterFund] {
        var behalten: [PlatzhalterFund] = []
        for fund in funde.sorted(by: { $0.bereich.length > $1.bereich.length }) {
            let kollidiert = behalten.contains {
                NSIntersectionRange($0.bereich, fund.bereich).length > 0
            }
            if !kollidiert { behalten.append(fund) }
        }
        return behalten.sorted { $0.bereich.location < $1.bereich.location }
    }
}
