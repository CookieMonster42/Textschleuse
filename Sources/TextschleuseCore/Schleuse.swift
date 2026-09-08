import Foundation

/// Das Ergebnis einer Analyse: der Originaltext, alles was gefunden wurde, und
/// eine Arbeitskopie des Wörterbuchs mit den Einträgen, die dabei neu entstanden
/// sind. Gespeichert wird die Kopie erst, wenn du im Popup Enter drückst.
public struct Analyse: Sendable {
    public var original: String
    public var funde: [Fund]
    public var woerterbuch: Woerterbuch
    /// Zuordnung `UNBEKANNT_3` → „Nyström" für den Rückweg. Lebt nur im
    /// Arbeitsspeicher und ist nach dem Beenden weg.
    public var unbekannte: [String: String]

    public init(
        original: String,
        funde: [Fund],
        woerterbuch: Woerterbuch,
        unbekannte: [String: String] = [:]
    ) {
        self.original = original
        self.funde = funde
        self.woerterbuch = woerterbuch
        self.unbekannte = unbekannte
    }

    public var aktiveFunde: [Fund] { funde.filter { !$0.verworfen } }
    public var vermutungen: [Fund] { funde.filter { $0.sicherheit == .vermutung && !$0.verworfen } }
    public var ungeprueft: [Fund] { funde.filter(\.brauchtPruefung) }
    public var regeltreffer: [Fund] { funde.filter { $0.quelle == .regel && !$0.verworfen } }

    /// Kurzfassung für die Kopfzeile im Popup: „8 IBAN, 5 E-Mail, 2 Telefon".
    public var regelZusammenfassung: [(kategorie: Kategorie, anzahl: Int)] {
        Dictionary(grouping: regeltreffer, by: \.kategorie)
            .map { (kategorie: $0.key, anzahl: $0.value.count) }
            .sorted { $0.anzahl > $1.anzahl }
    }
}

public enum Schleuse {

    // MARK: Analyse

    public static func analysiere(_ text: String, woerterbuch: Woerterbuch) -> Analyse {
        var arbeitsbuch = woerterbuch
        let nsText = text as NSString

        var funde = findeAusWoerterbuch(in: nsText, woerterbuch: arbeitsbuch)
        funde += Regelwerk.finde(in: text)
        funde += Heuristik.finde(in: text, woerterbuch: arbeitsbuch)
        funde = funde.ohneUeberschneidungen()

        var unbekannte: [String: String] = [:]
        var naechsteUnbekannt = 1
        var vergebeneUnbekannte: [String: String] = [:]  // Klartext → Platzhalter

        for index in funde.indices {
            switch funde[index].quelle {
            case .woerterbuch:
                break  // Platzhalter steht schon

            case .regel:
                // Derselbe Wert soll in einem Jahr denselben Platzhalter
                // bekommen, sonst bricht der Rückweg bei einer späteren Antwort.
                if let vorhanden = arbeitsbuch.eintrag(fuerText: funde[index].text) {
                    funde[index].eintragId = vorhanden.id
                    funde[index].platzhalter = vorhanden.platzhalter
                } else {
                    let neu = arbeitsbuch.anlegen(
                        text: funde[index].text,
                        kategorie: funde[index].kategorie,
                        automatischErkannt: true
                    )
                    funde[index].eintragId = neu.id
                    funde[index].platzhalter = neu.platzhalter
                }

            case .heuristik:
                // Unbestätigte Vermutungen bekommen eine laufende Nummer, die
                // nur für diesen Text gilt.
                let schluessel = funde[index].text.lowercased()
                if let schon = vergebeneUnbekannte[schluessel] {
                    funde[index].platzhalter = schon
                } else {
                    let platzhalter = "\(Kategorie.unbekannt.praefix)_\(naechsteUnbekannt)"
                    naechsteUnbekannt += 1
                    vergebeneUnbekannte[schluessel] = platzhalter
                    funde[index].platzhalter = platzhalter
                    unbekannte[platzhalter] = funde[index].text
                }
            }
        }

        return Analyse(
            original: text,
            funde: funde,
            woerterbuch: arbeitsbuch,
            unbekannte: unbekannte
        )
    }

    /// Alle Schreibweisen aller Einträge im Text suchen. Längere zuerst, damit
    /// „Thorben Nyström" gewinnt und nicht in zwei Funde zerfällt.
    static func findeAusWoerterbuch(in text: NSString, woerterbuch: Woerterbuch) -> [Fund] {
        var funde: [Fund] = []
        for eintrag in woerterbuch.eintraege {
            for schreibweise in eintrag.alleSchreibweisen {
                guard let regex = Varianten.regex(fuer: schreibweise.text) else { continue }
                let treffer = regex.matches(
                    in: text as String,
                    range: NSRange(location: 0, length: text.length)
                )
                for einzeln in treffer {
                    funde.append(Fund(
                        bereich: einzeln.range,
                        text: text.substring(with: einzeln.range),
                        kategorie: eintrag.kategorie,
                        sicherheit: .sicher,
                        quelle: .woerterbuch,
                        eintragId: eintrag.id,
                        platzhalter: schreibweise.platzhalter
                    ))
                }
            }
        }
        return funde
    }

    // MARK: Entscheidungen im Popup

    /// Bestätigt eine Vermutung: sie bekommt einen echten Eintrag im
    /// Wörterbuch und damit einen dauerhaften Platzhalter.
    public static func bestaetige(
        fundId: UUID,
        als kategorie: Kategorie,
        in analyse: inout Analyse,
        merken: Bool = true
    ) {
        guard let index = analyse.funde.firstIndex(where: { $0.id == fundId }) else { return }
        let text = analyse.funde[index].text

        let eintrag: Eintrag
        if let vorhanden = analyse.woerterbuch.eintrag(fuerText: text) {
            eintrag = vorhanden
        } else if merken {
            eintrag = analyse.woerterbuch.anlegen(text: text, kategorie: kategorie)
        } else {
            // Nicht merken heißt: echter Platzhalter, aber nur für diesen Text.
            analyse.funde[index].kategorie = kategorie
            analyse.funde[index].bestaetigt = true
            analyse.funde[index].sicherheit = .sicher
            return
        }

        // Alle gleichlautenden Funde mitziehen, nicht nur den angeklickten.
        let gesucht = text.lowercased()
        for weiterer in analyse.funde.indices where analyse.funde[weiterer].text.lowercased() == gesucht {
            let alterPlatzhalter = analyse.funde[weiterer].platzhalter
            analyse.unbekannte.removeValue(forKey: alterPlatzhalter)
            analyse.funde[weiterer].kategorie = kategorie
            analyse.funde[weiterer].eintragId = eintrag.id
            analyse.funde[weiterer].platzhalter = eintrag.platzhalter
            analyse.funde[weiterer].sicherheit = .sicher
            analyse.funde[weiterer].bestaetigt = true
        }

        ergaenzeNachnamen(von: eintrag, in: &analyse)
    }

    /// Sobald „Ilse Bergkamp" bestätigt ist, wird das einzelne „Bergkamp"
    /// weiter unten im Text interessant. Vorher war es nur ein
    /// großgeschriebenes Wort und niemand hat danach gesucht.
    ///
    /// Ohne diesen Nachschlag bestätigst du die volle Nennung und die Kurzform
    /// geht im Klartext raus, ohne dass irgendwo ein Hinweis auftaucht.
    private static func ergaenzeNachnamen(von eintrag: Eintrag, in analyse: inout Analyse) {
        guard eintrag.kategorie == .person else { return }
        let nsText = analyse.original as NSString
        let neue = Heuristik.findeNachnamenBekannterPersonen(
            in: nsText,
            woerterbuch: analyse.woerterbuch
        )

        for var fund in neue {
            let kollidiert = analyse.funde.contains {
                NSIntersectionRange($0.bereich, fund.bereich).length > 0
            }
            guard !kollidiert else { continue }

            // Auch der Nachschlag braucht eine Nummer, sonst steht er als
            // Klartext im Ergebnis.
            let platzhalter = "\(Kategorie.unbekannt.praefix)_\(naechsteFreieUnbekannte(in: analyse))"
            fund.platzhalter = platzhalter
            analyse.unbekannte[platzhalter] = fund.text
            analyse.funde.append(fund)
        }
        analyse.funde.sort { $0.bereich.location < $1.bereich.location }
    }

    private static func naechsteFreieUnbekannte(in analyse: Analyse) -> Int {
        let benutzt = analyse.unbekannte.keys.compactMap { schluessel -> Int? in
            guard schluessel.hasPrefix("\(Kategorie.unbekannt.praefix)_") else { return nil }
            return Int(schluessel.dropFirst(Kategorie.unbekannt.praefix.count + 1))
        }
        return (benutzt.max() ?? 0) + 1
    }

    /// Hängt eine Vermutung als weitere Schreibweise an einen bekannten
    /// Eintrag: aus „Nyström" wird `PERSON_7B` statt eines eigenen Eintrags.
    public static func alsAliasZuordnen(
        fundId: UUID,
        zu eintragId: UUID,
        in analyse: inout Analyse
    ) {
        guard let index = analyse.funde.firstIndex(where: { $0.id == fundId }),
              let alias = analyse.woerterbuch.aliasHinzufuegen(analyse.funde[index].text, zu: eintragId),
              let eintrag = analyse.woerterbuch.eintrag(mitId: eintragId)
        else { return }

        let gesucht = analyse.funde[index].text.lowercased()
        for weiterer in analyse.funde.indices where analyse.funde[weiterer].text.lowercased() == gesucht {
            analyse.unbekannte.removeValue(forKey: analyse.funde[weiterer].platzhalter)
            analyse.funde[weiterer].kategorie = eintrag.kategorie
            analyse.funde[weiterer].eintragId = eintrag.id
            analyse.funde[weiterer].platzhalter = eintrag.platzhalter(fuer: alias)
            analyse.funde[weiterer].sicherheit = .sicher
            analyse.funde[weiterer].bestaetigt = true
        }
    }

    /// Wirft einen Fund raus. Der Klartext bleibt dann im Ergebnis stehen.
    public static func verwerfe(fundId: UUID, in analyse: inout Analyse) {
        guard let index = analyse.funde.firstIndex(where: { $0.id == fundId }) else { return }
        analyse.funde[index].verworfen = true
    }

    // MARK: Ergebnis

    /// Baut den geschützten Text. Ersetzt wird von hinten nach vorn, damit die
    /// Bereiche der noch nicht bearbeiteten Funde gültig bleiben.
    public static func geschuetzterText(_ analyse: Analyse) -> String {
        let ergebnis = NSMutableString(string: analyse.original)
        for fund in analyse.aktiveFunde.sorted(by: { $0.bereich.location > $1.bereich.location }) {
            ergebnis.replaceCharacters(in: fund.bereich, with: fund.platzhalter)
        }
        return ergebnis as String
    }

    /// Der Text, der in die Zwischenablage geht: Hinweise plus geschützter Text.
    public static func fuerZwischenablage(_ analyse: Analyse, mitHinweisen: Bool = true) -> String {
        let text = geschuetzterText(analyse)
        guard mitHinweisen else { return text }
        return Hinweise.vorspann(fuer: analyse) + text
    }
}
