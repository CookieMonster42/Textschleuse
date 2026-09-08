import Foundation

/// Vermutungen. Alles hier landet rot im Popup und muss von dir bestätigt
/// werden, bevor der echte Platzhalter greift.
///
/// Bewusst nicht enthalten ist die Regel „zwei großgeschriebene Wörter
/// hintereinander". Im Deutschen sind alle Substantive groß, damit trifft sie
/// „Herzlichen Dank" so oft wie einen Namen und macht das Popup unbrauchbar.
public enum Heuristik {

    /// Wörter, die am Satzanfang oder in Floskeln groß stehen und keine Namen
    /// sind.
    static let stoppwoerter: Set<String> = [
        "sehr", "geehrte", "geehrter", "geehrtes", "liebe", "lieber", "hallo", "guten",
        "mit", "freundlichen", "grüßen", "gruessen", "viele", "beste", "herzliche",
        "der", "die", "das", "dem", "den", "des", "ein", "eine", "einen", "einem",
        "und", "oder", "aber", "wir", "sie", "ich", "es", "im", "in", "am", "an",
        "für", "fuer", "von", "bei", "zur", "zum", "auf", "aus", "nach", "über",
        "betreff", "anlage", "anbei", "bitte", "danke", "vielen", "dank", "gerne",
        "januar", "februar", "märz", "maerz", "april", "mai", "juni", "juli",
        "august", "september", "oktober", "november", "dezember",
        "montag", "dienstag", "mittwoch", "donnerstag", "freitag", "samstag", "sonntag",
    ]

    /// Rechtsformen. Was davorsteht, ist mit hoher Wahrscheinlichkeit ein
    /// Firmenname.
    static let rechtsformen = [
        "GmbH & Co. KG", "gGmbH", "GmbH", "AG", "SE", "KGaA", "KG", "OHG", "GbR",
        "e.V.", "eG", "mbH", "UG", "Ltd.", "PLC", "S.A.", "B.V.", "N.V.",
    ]

    static let anreden = ["Herr", "Herrn", "Frau", "Hr.", "Fr.", "Dr.", "Prof.", "Dipl.-Ing."]

    /// Ein großgeschriebenes Namenswort: beginnt mit Großbuchstabe, darf
    /// Bindestrich und Apostroph enthalten.
    static let namenswort = "[A-ZÄÖÜ][\\p{L}]*(?:[-'\u{2019}][A-ZÄÖÜ]?[\\p{L}]+)*"

    public static func finde(in text: String, woerterbuch: Woerterbuch) -> [Fund] {
        let nsText = text as NSString
        var funde: [Fund] = []
        funde += findePersonenNachVorname(in: nsText)
        funde += findePersonenNachAnrede(in: nsText)
        funde += findeNachnamenBekannterPersonen(in: nsText, woerterbuch: woerterbuch)
        funde += findeFirmen(in: nsText)
        funde += findeOrte(in: nsText)
        return funde.map { fund in
            var kopie = fund
            if fund.kategorie == .person,
               let verwandt = woerterbuch.verwandtePersonen(zu: fund.text).first {
                kopie.gruppenVorschlag = verwandt.id
            }
            return kopie
        }
    }

    // MARK: Personen über die Vornamensliste

    /// Der Nachname steht in einer Vorausschau, nicht im Treffer selbst.
    /// Sonst verschluckt ein Wort wie „Grüßen" den Namen dahinter: es passt auf
    /// das erste Namenswort, scheitert an der Vornamensliste, und „Ilse" ist
    /// mitkonsumiert, bevor es geprüft wird. Getrennt werden darf nur durch
    /// Leerzeichen, nicht durch einen Zeilenumbruch.
    static func findePersonenNachVorname(in text: NSString) -> [Fund] {
        let muster = "\\b(\(namenswort))(?=(?:[^\\S\\n]+(\(namenswort)))?)"
        var funde: [Fund] = []

        for treffer in RegexWerkzeug.treffer(muster, in: text) {
            let ersterBereich = treffer.range(at: 1)
            guard ersterBereich.location != NSNotFound else { continue }
            let erstes = text.substring(with: ersterBereich)
            guard Vornamen.kenntVorname(erstes) else { continue }

            let zweiterBereich = treffer.range(at: 2)
            let hatNachnamen = zweiterBereich.location != NSNotFound
                && !stoppwoerter.contains(text.substring(with: zweiterBereich).lowercased())

            // Mehrdeutige Namen wie „Mai" oder „Frank" zählen nur, wenn ein
            // Nachname folgt. Sonst wird aus jedem Datum eine Person.
            if Vornamen.istMehrdeutig(erstes) && !hatNachnamen { continue }

            let bereich = hatNachnamen
                ? NSUnionRange(ersterBereich, zweiterBereich)
                : ersterBereich

            funde.append(Fund(
                bereich: bereich,
                text: text.substring(with: bereich),
                kategorie: .person,
                sicherheit: .vermutung,
                quelle: .heuristik
            ))
        }
        return funde
    }

    // MARK: Personen über Anrede und Titel

    /// „Sehr geehrter Herr Nyström" markiert nur „Nyström". Die Anrede bleibt
    /// im Text stehen, damit das Modell weiter weiß, wie es antworten soll.
    static func findePersonenNachAnrede(in text: NSString) -> [Fund] {
        let anredeMuster = anreden
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        let muster = "(?:\(anredeMuster))\\s+(?:(?:Dr|Prof|Dipl)\\.[\\s\\-]*)*(\(namenswort))(?:\\s+(\(namenswort)))?"

        var funde: [Fund] = []
        for treffer in RegexWerkzeug.treffer(muster, in: text) {
            let ersterBereich = treffer.range(at: 1)
            guard ersterBereich.location != NSNotFound else { continue }
            let erstes = text.substring(with: ersterBereich)
            guard !stoppwoerter.contains(erstes.lowercased()) else { continue }

            let zweiterBereich = treffer.range(at: 2)
            let hatZweites = zweiterBereich.location != NSNotFound
                && !stoppwoerter.contains(text.substring(with: zweiterBereich).lowercased())
            let bereich = hatZweites ? NSUnionRange(ersterBereich, zweiterBereich) : ersterBereich

            funde.append(Fund(
                bereich: bereich,
                text: text.substring(with: bereich),
                kategorie: .person,
                sicherheit: .vermutung,
                quelle: .heuristik
            ))
        }
        return funde
    }

    // MARK: Nachnamen bereits gemerkter Personen

    /// Steht „Thorben Nyström" im Wörterbuch, dann ist ein einzelnes „Nyström"
    /// weiter unten im Text sehr wahrscheinlich dieselbe Person. Der Fund
    /// bringt den Eintrag als Gruppenvorschlag mit, damit das Popup ihn mit
    /// einem Tastendruck als weitere Schreibweise anhängen kann.
    ///
    /// Bewusst eine Vermutung und keine harte Ersetzung: „Nyström" kann auch
    /// der Bruder sein.
    static func findeNachnamenBekannterPersonen(
        in text: NSString,
        woerterbuch: Woerterbuch
    ) -> [Fund] {
        var funde: [Fund] = []
        for eintrag in woerterbuch.eintraege where eintrag.kategorie == .person {
            let teile = eintrag.text.split(separator: " ").map(String.init)
            guard teile.count > 1, let nachname = teile.last, nachname.count >= 3 else { continue }
            // Schon als eigene Schreibweise hinterlegt? Dann findet der
            // Wörterbuchdurchlauf ihn und der Fund hier wäre doppelt.
            let bekannt = eintrag.aliase.contains { $0.text.caseInsensitiveCompare(nachname) == .orderedSame }
            guard !bekannt, let regex = Varianten.regex(fuer: nachname) else { continue }

            let treffer = regex.matches(
                in: text as String,
                range: NSRange(location: 0, length: text.length)
            )
            for einzeln in treffer {
                var fund = Fund(
                    bereich: einzeln.range,
                    text: text.substring(with: einzeln.range),
                    kategorie: .person,
                    sicherheit: .vermutung,
                    quelle: .heuristik
                )
                fund.gruppenVorschlag = eintrag.id
                funde.append(fund)
            }
        }
        return funde
    }

    // MARK: Firmen über die Rechtsform

    static func findeFirmen(in text: NSString) -> [Fund] {
        let formen = rechtsformen
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        // Bis zu vier Namenswörter vor der Rechtsform, „&" erlaubt.
        let muster = "\\b(?:\(namenswort)|&)(?:\\s+(?:\(namenswort)|&)){0,3}\\s+(?:\(formen))"

        return RegexWerkzeug.treffer(muster, in: text).map { treffer in
            Fund(
                bereich: treffer.range,
                text: text.substring(with: treffer.range),
                kategorie: .firma,
                sicherheit: .vermutung,
                quelle: .heuristik
            )
        }
    }

    // MARK: Orte über die Postleitzahl

    static func findeOrte(in text: NSString) -> [Fund] {
        let muster = "\\b\\d{5}\\s+(\(namenswort))"
        return RegexWerkzeug.treffer(muster, in: text).compactMap { treffer in
            let ortBereich = treffer.range(at: 1)
            guard ortBereich.location != NSNotFound else { return nil }
            let ort = text.substring(with: ortBereich)
            guard !stoppwoerter.contains(ort.lowercased()) else { return nil }
            return Fund(
                bereich: treffer.range,
                text: text.substring(with: treffer.range),
                kategorie: .ort,
                sicherheit: .vermutung,
                quelle: .heuristik
            )
        }
    }
}
