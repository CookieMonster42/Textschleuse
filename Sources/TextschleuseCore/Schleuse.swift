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
        funde += Regelwerk.finde(in: text, zusaetzlich: arbeitsbuch.zusatzregeln)
        // Die Freiliste bremst nur Vermutungen. Sie greift vor der
        // Überschneidungsprüfung, damit ein weggefallenes „August" Platz für
        // den längeren Datumstreffer macht statt ihn zu verdrängen.
        funde += Heuristik.finde(in: text, woerterbuch: arbeitsbuch)
            .filter { !arbeitsbuch.istFrei($0.text) }
        funde = funde.ohneUeberschneidungen()

        var unbekannte: [String: String] = [:]
        var vergebeneUnbekannte: [String: String] = [:]  // Klartext → Platzhalter

        for index in funde.indices {
            switch funde[index].quelle {
            case .woerterbuch, .markierung:
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
                // Unbestätigte Vermutungen bekommen eine Zufallskennung, die
                // nur für diesen Text gilt.
                let schluessel = funde[index].text.lowercased()
                if let schon = vergebeneUnbekannte[schluessel] {
                    funde[index].platzhalter = schon
                } else {
                    let platzhalter = freierPlatzhalter(
                        fuer: .unbekannt,
                        belegt: Set(unbekannte.keys).union(arbeitsbuch.alleDecknamen)
                    )
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

        // Auch eine bestätigte Vermutung kann weiter unten im Text noch
        // einmal stehen, ohne dass die Heuristik sie dort gesehen hat.
        ergaenzeWeitereVorkommen(
            eintrag.alleSchreibweisen,
            kategorie: eintrag.kategorie,
            eintragId: eintrag.id,
            quelle: .woerterbuch,
            in: &analyse
        )
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

            // Auch der Nachschlag braucht einen Decknamen, sonst steht er als
            // Klartext im Ergebnis.
            let platzhalter = freierPlatzhalter(fuer: .unbekannt, in: analyse)
            fund.platzhalter = platzhalter
            analyse.unbekannte[platzhalter] = fund.text
            analyse.funde.append(fund)
        }
        analyse.funde.sort { $0.bereich.location < $1.bereich.location }
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

        ergaenzeWeitereVorkommen(
            eintrag.alleSchreibweisen,
            kategorie: eintrag.kategorie,
            eintragId: eintrag.id,
            quelle: .woerterbuch,
            in: &analyse
        )
    }

    // MARK: Freie Markierung

    /// Macht aus einer Textmarkierung eine Fundstelle. Was die Regeln und die
    /// Heuristik übersehen haben, holst du damit selbst.
    ///
    /// Bestehende Funde, die in der Markierung liegen, verschwinden: du hast
    /// gerade ausdrücklich gesagt, was hier gilt.
    @discardableResult
    /// Prüft einen geänderten Text noch einmal und nimmt dabei mit, was du
    /// schon entschieden hattest.
    ///
    /// Ohne das war jede Korrektur im Text teuer: ein Buchstabe getippt, und
    /// alle verworfenen Begriffe standen wieder als Fundstelle da, alle von
    /// Hand markierten waren weg. Was hier überlebt:
    ///
    /// - Verworfene Begriffe bleiben verworfen, überall im Text.
    /// - Von Hand markierte Stellen werden neu gesucht und wieder gesetzt.
    /// - Bestätigte Vermutungen bleiben bestätigt.
    /// - Die Sitzungsdecknamen (`UNBEKANNT_n`) bleiben dieselben.
    public static func analysiereErneut(_ text: String, wie vorherige: Analyse) -> Analyse {
        var neue = analysiere(text, woerterbuch: vorherige.woerterbuch)
        neue.unbekannte = vorherige.unbekannte

        // Von Hand Markiertes zuerst: es schlägt jede Automatik und muss
        // deshalb wieder im Text stehen, bevor Entscheidungen greifen.
        let nsText = text as NSString
        for alter in vorherige.funde where alter.quelle == .markierung && !alter.verworfen {
            let schonDa = neue.funde.contains {
                $0.text.compare(alter.text, options: .caseInsensitive) == .orderedSame
            }
            guard !schonDa else { continue }
            var suchab = 0
            while suchab < nsText.length {
                let rest = NSRange(location: suchab, length: nsText.length - suchab)
                let treffer = nsText.range(of: alter.text, options: [], range: rest)
                guard treffer.location != NSNotFound else { break }
                _ = markiere(
                    bereich: treffer,
                    als: alter.kategorie,
                    merken: false,
                    in: &neue
                )
                suchab = NSMaxRange(treffer)
            }
        }

        let verworfen = Set(vorherige.funde.filter(\.verworfen).map { $0.text.lowercased() })
        let bestaetigt = Set(vorherige.funde.filter(\.bestaetigt).map { $0.text.lowercased() })
        for index in neue.funde.indices {
            let wortlaut = neue.funde[index].text.lowercased()
            if verworfen.contains(wortlaut) {
                neue.funde[index].verworfen = true
                if neue.funde[index].eintragId == nil {
                    neue.unbekannte.removeValue(forKey: neue.funde[index].platzhalter)
                }
            } else if bestaetigt.contains(wortlaut) {
                neue.funde[index].bestaetigt = true
            }
        }
        return neue
    }

    public static func markiere(
        bereich: NSRange,
        als kategorie: Kategorie,
        merken: Bool,
        in analyse: inout Analyse
    ) -> UUID? {
        let nsText = analyse.original as NSString
        let geputzt = bereinige(bereich, in: nsText)
        guard geputzt.length > 0 else { return nil }

        let text = nsText.substring(with: geputzt)

        // Weg mit allem, was hier liegt — und mit jeder anderen Stelle, an der
        // dasselbe steht. Wer einen Begriff ausdrücklich markiert, sagt damit
        // etwas über den Begriff, nicht über diese eine Stelle. Hatte er ihn
        // vorher verworfen, ist das hiermit widerrufen.
        let gesucht = text.lowercased()
        analyse.funde.removeAll {
            NSIntersectionRange($0.bereich, geputzt).length > 0 || $0.text.lowercased() == gesucht
        }

        var fund = Fund(
            bereich: geputzt,
            text: text,
            kategorie: kategorie,
            sicherheit: .sicher,
            quelle: .markierung
        )
        fund.bestaetigt = true

        if merken {
            let eintrag = analyse.woerterbuch.eintrag(fuerText: text)
                ?? analyse.woerterbuch.anlegen(text: text, kategorie: kategorie)
            fund.eintragId = eintrag.id
            fund.platzhalter = eintrag.platzhalter
        } else {
            fund.platzhalter = freierPlatzhalter(fuer: kategorie, in: analyse)
            analyse.unbekannte[fund.platzhalter] = text
        }

        analyse.funde.append(fund)
        analyse.funde.sort { $0.bereich.location < $1.bereich.location }

        // Gleichlautende Stellen, die schon Fundstellen sind, ziehen mit.
        if merken, let eintragId = fund.eintragId {
            uebernimmFuerGleichlautende(text: text, eintragId: eintragId, in: &analyse)
        }

        // Und der ganze Text wird nach weiteren Vorkommen durchsucht, die
        // vorher niemandem aufgefallen sind.
        ergaenzeWeitereVorkommen(
            schreibweisen(fuer: fund, in: analyse),
            kategorie: kategorie,
            eintragId: fund.eintragId,
            quelle: .markierung,
            in: &analyse
        )
        return fund.id
    }

    /// Macht aus einer Markierung eine weitere Schreibweise eines bekannten
    /// Eintrags.
    ///
    /// Für den Fall, dass derselbe Mensch im Text anders dasteht als im
    /// Wörterbuch und die Automatik ihn deshalb für jemand anderen hält. Der
    /// Platzhalter wird `PERSON_3B` statt eines eigenen Eintrags — damit
    /// bleibt beim Lesen der KI-Antwort klar, dass beides dieselbe Person ist.
    @discardableResult
    public static func markiereAlsSchreibweise(
        bereich: NSRange,
        zu eintragId: UUID,
        in analyse: inout Analyse
    ) -> UUID? {
        let nsText = analyse.original as NSString
        let geputzt = bereinige(bereich, in: nsText)
        guard geputzt.length > 0,
              analyse.woerterbuch.eintrag(mitId: eintragId) != nil
        else { return nil }

        let text = nsText.substring(with: geputzt)
        analyse.funde.removeAll { NSIntersectionRange($0.bereich, geputzt).length > 0 }

        guard let alias = analyse.woerterbuch.aliasHinzufuegen(text, zu: eintragId),
              let eintrag = analyse.woerterbuch.eintrag(mitId: eintragId)
        else { return nil }

        var fund = Fund(
            bereich: geputzt,
            text: text,
            kategorie: eintrag.kategorie,
            sicherheit: .sicher,
            quelle: .markierung,
            eintragId: eintrag.id,
            platzhalter: eintrag.platzhalter(fuer: alias)
        )
        fund.bestaetigt = true
        analyse.funde.append(fund)
        analyse.funde.sort { $0.bereich.location < $1.bereich.location }

        ergaenzeWeitereVorkommen(
            eintrag.alleSchreibweisen,
            kategorie: eintrag.kategorie,
            eintragId: eintrag.id,
            quelle: .woerterbuch,
            in: &analyse
        )
        return fund.id
    }

    /// Schneidet Leerzeichen und Satzzeichen an den Rändern weg. Wer mit der
    /// Maus markiert, erwischt fast immer ein Leerzeichen zu viel.
    private static func bereinige(_ bereich: NSRange, in text: NSString) -> NSRange {
        guard bereich.location != NSNotFound,
              bereich.length > 0,
              NSMaxRange(bereich) <= text.length
        else { return NSRange(location: 0, length: 0) }

        let unerwuenscht = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ".,;:!?()[]{}\"'„“”‚‘’«»–—"))

        var start = bereich.location
        var ende = NSMaxRange(bereich)
        while start < ende, let zeichen = text.substring(with: NSRange(location: start, length: 1)).unicodeScalars.first,
              unerwuenscht.contains(zeichen) {
            start += 1
        }
        while ende > start, let zeichen = text.substring(with: NSRange(location: ende - 1, length: 1)).unicodeScalars.first,
              unerwuenscht.contains(zeichen) {
            ende -= 1
        }
        return NSRange(location: start, length: ende - start)
    }

    /// Ein Platzhalter, der in diesem Text noch frei ist. Für Markierungen, die
    /// nicht ins Wörterbuch sollen, und für die Unbekannten.
    private static func freierPlatzhalter(fuer kategorie: Kategorie, in analyse: Analyse) -> String {
        let belegt = Set(analyse.funde.map(\.platzhalter))
            .union(analyse.unbekannte.keys)
            .union(analyse.woerterbuch.alleDecknamen)
        return freierPlatzhalter(fuer: kategorie, belegt: belegt)
    }

    private static func freierPlatzhalter(fuer kategorie: Kategorie, belegt: Set<String>) -> String {
        var name: String
        repeat {
            name = "\(kategorie.praefix)_\(Decknamen.kennung(fuer: kategorie, belegt: belegt))"
        } while belegt.contains(name)
        return name
    }

    private static func uebernimmFuerGleichlautende(
        text: String,
        eintragId: UUID,
        in analyse: inout Analyse
    ) {
        guard let eintrag = analyse.woerterbuch.eintrag(mitId: eintragId) else { return }
        let gesucht = text.lowercased()
        for index in analyse.funde.indices
        where analyse.funde[index].text.lowercased() == gesucht && analyse.funde[index].eintragId == nil {
            analyse.unbekannte.removeValue(forKey: analyse.funde[index].platzhalter)
            analyse.funde[index].kategorie = eintrag.kategorie
            analyse.funde[index].eintragId = eintrag.id
            analyse.funde[index].platzhalter = eintrag.platzhalter
            analyse.funde[index].sicherheit = .sicher
            analyse.funde[index].bestaetigt = true
        }
    }

    // MARK: Nachsuchen

    /// Sucht einen gerade festgelegten Begriff im ganzen Text und legt für
    /// jedes weitere Vorkommen eine Fundstelle an.
    ///
    /// Ohne das schützt du „Nordlicht" an der einen Stelle, an der du es
    /// markiert hast, und drei Absätze weiter steht es im Klartext. Gesucht
    /// wird mit denselben Schreibvarianten wie beim Wörterbuch, gebeugte
    /// Formen also eingeschlossen.
    ///
    /// Stellen, an denen schon eine Fundstelle liegt, bleiben unangetastet —
    /// auch verworfene. Wer dort ausdrücklich Nein gesagt hat, soll es nicht
    /// durch die Hintertür zurückbekommen.
    @discardableResult
    static func ergaenzeWeitereVorkommen(
        _ schreibweisen: [(text: String, platzhalter: String)],
        kategorie: Kategorie,
        eintragId: UUID?,
        quelle: Quelle,
        in analyse: inout Analyse
    ) -> Int {
        let nsText = analyse.original as NSString
        let ganzerText = NSRange(location: 0, length: nsText.length)
        var neue: [Fund] = []

        // Längere Schreibweisen zuerst, damit „Thorben Nyström" gewinnt und
        // nicht in zwei Funde zerfällt.
        for (begriff, platzhalter) in schreibweisen.sorted(by: { $0.text.count > $1.text.count }) {
            // Bei ein oder zwei Zeichen trifft die Suche zu viel. Die
            // markierte Stelle selbst steht schon, nur das Nachsuchen entfällt.
            guard begriff.count >= 3, let regex = Varianten.regex(fuer: begriff) else { continue }

            for treffer in regex.matches(in: analyse.original, range: ganzerText) {
                let belegt = analyse.funde.contains {
                    NSIntersectionRange($0.bereich, treffer.range).length > 0
                } || neue.contains {
                    NSIntersectionRange($0.bereich, treffer.range).length > 0
                }
                guard !belegt else { continue }

                var fund = Fund(
                    bereich: treffer.range,
                    text: nsText.substring(with: treffer.range),
                    kategorie: kategorie,
                    sicherheit: .sicher,
                    quelle: quelle,
                    eintragId: eintragId,
                    platzhalter: platzhalter
                )
                fund.bestaetigt = true
                neue.append(fund)
            }
        }

        guard !neue.isEmpty else { return 0 }
        analyse.funde.append(contentsOf: neue)
        analyse.funde.sort { $0.bereich.location < $1.bereich.location }
        return neue.count
    }

    /// Die Schreibweisen, unter denen ein Fund im Text noch stecken kann.
    private static func schreibweisen(fuer fund: Fund, in analyse: Analyse) -> [(text: String, platzhalter: String)] {
        if let eintragId = fund.eintragId,
           let eintrag = analyse.woerterbuch.eintrag(mitId: eintragId) {
            return eintrag.alleSchreibweisen
        }
        return [(text: fund.text, platzhalter: fund.platzhalter)]
    }

    // MARK: Originaltext einer Fundstelle

    public enum TextFehler: LocalizedError, Equatable {
        case leer

        public var errorDescription: String? {
            switch self {
            case .leer:
                return "Leer geht nicht. Wenn die Stelle gar nicht geschützt werden soll, wirf sie raus."
            }
        }
    }

    /// Ersetzt den Originaltext einer Fundstelle.
    ///
    /// Für den Fall, dass die Erkennung zu viel oder zu wenig erwischt hat —
    /// „Herrn Nyström" statt „Nyström" — oder dass im eingefügten Text ein
    /// Tippfehler steckt. Alle Fundstellen dahinter rücken mit, sonst zeigen
    /// ihre Bereiche nach der Änderung auf die falschen Zeichen.
    ///
    /// Der Deckname bleibt: du korrigierst, wie die Stelle dasteht, nicht wen
    /// sie meint.
    public static func ersetzeOriginaltext(
        fundId: UUID,
        durch neuerText: String,
        in analyse: inout Analyse
    ) throws {
        let geputzt = neuerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !geputzt.isEmpty else { throw TextFehler.leer }
        guard let index = analyse.funde.firstIndex(where: { $0.id == fundId }) else { return }

        let alterBereich = analyse.funde[index].bereich
        guard analyse.funde[index].text != geputzt else { return }

        let text = NSMutableString(string: analyse.original)
        guard NSMaxRange(alterBereich) <= text.length else { return }
        text.replaceCharacters(in: alterBereich, with: geputzt)

        let neueLaenge = (geputzt as NSString).length
        let verschiebung = neueLaenge - alterBereich.length

        analyse.original = text as String
        analyse.funde[index].text = geputzt
        analyse.funde[index].bereich = NSRange(location: alterBereich.location, length: neueLaenge)

        // Alles, was hinter der geänderten Stelle liegt, rückt mit.
        for weiterer in analyse.funde.indices where weiterer != index {
            let bereich = analyse.funde[weiterer].bereich
            guard bereich.location >= NSMaxRange(alterBereich) else { continue }
            analyse.funde[weiterer].bereich = NSRange(
                location: bereich.location + verschiebung,
                length: bereich.length
            )
        }

        // Die Sitzungszuordnung zeigt sonst weiter auf die alte Schreibweise.
        if analyse.funde[index].eintragId == nil {
            analyse.unbekannte[analyse.funde[index].platzhalter] = geputzt
        }
        analyse.funde.sort { $0.bereich.location < $1.bereich.location }
    }

    // MARK: Deckname

    /// Gibt der Fundstelle einen anderen Decknamen.
    ///
    /// Hängt die Fundstelle an einem Wörterbucheintrag, wird der Eintrag
    /// umbenannt und der bisherige Name bleibt auflösbar. Sonst gilt der Name
    /// nur für diesen Text.
    public static func benenneUm(
        fundId: UUID,
        auf name: String,
        in analyse: inout Analyse
    ) throws {
        guard let index = analyse.funde.firstIndex(where: { $0.id == fundId }) else { return }

        guard let eintragId = analyse.funde[index].eintragId else {
            let geprueft = try analyse.woerterbuch.pruefeDeckname(name, fuer: nil)
            let anderweitigBelegt = analyse.funde
                .filter { $0.id != fundId }
                .contains { $0.platzhalter.uppercased() == geprueft }
            guard !anderweitigBelegt else {
                throw Woerterbuch.DecknamenFehler.vergeben(geprueft)
            }
            let bisher = analyse.funde[index].platzhalter
            analyse.unbekannte.removeValue(forKey: bisher)
            analyse.funde[index].platzhalter = geprueft
            analyse.unbekannte[geprueft] = analyse.funde[index].text
            return
        }

        try analyse.woerterbuch.umbenennen(eintragId, auf: name)
        aktualisierePlatzhalter(fuerEintrag: eintragId, in: &analyse)
    }

    /// Zieht die Platzhalter aller Funde nach, die an einem Eintrag hängen.
    static func aktualisierePlatzhalter(fuerEintrag eintragId: UUID, in analyse: inout Analyse) {
        guard let eintrag = analyse.woerterbuch.eintrag(mitId: eintragId) else { return }
        for index in analyse.funde.indices where analyse.funde[index].eintragId == eintragId {
            let text = analyse.funde[index].text.lowercased()
            if let alias = eintrag.aliase.first(where: { $0.text.lowercased() == text }) {
                analyse.funde[index].platzhalter = eintrag.platzhalter(fuer: alias)
            } else {
                analyse.funde[index].platzhalter = eintrag.platzhalter
            }
        }
    }

    /// Wirft einen Fund raus — und mit ihm jede andere Stelle, an der genau
    /// dasselbe steht.
    ///
    /// „Sally ist in diesem Text kein Name" gilt für den ganzen Text. Alles
    /// andere wäre Handarbeit an jedem einzelnen Vorkommen, und beim
    /// dreizehnten übersieht man eines.
    ///
    /// Groß- und Kleinschreibung ist dabei egal, die Schreibweise nicht: „Jan
    /// Maia" trifft nicht „Jan  Maia" mit zwei Leerzeichen. Wer die auch
    /// loswerden will, verwirft sie einzeln — sie ist ja auch eine eigene
    /// Fundstelle.
    @discardableResult
    public static func verwerfe(fundId: UUID, in analyse: inout Analyse) -> Int {
        guard let fund = analyse.funde.first(where: { $0.id == fundId }) else { return 0 }
        let gesucht = fund.text.lowercased()

        var betroffen = 0
        for index in analyse.funde.indices
        where analyse.funde[index].text.lowercased() == gesucht && !analyse.funde[index].verworfen {
            analyse.funde[index].verworfen = true
            // Eine verworfene Stelle braucht keine Sitzungszuordnung mehr; ihr
            // Platzhalter taucht im Ergebnis gar nicht auf.
            if analyse.funde[index].eintragId == nil {
                analyse.unbekannte.removeValue(forKey: analyse.funde[index].platzhalter)
            }
            betroffen += 1
        }
        return betroffen
    }

    /// Nimmt das Verwerfen zurück, ebenfalls für alle gleichlautenden Stellen.
    @discardableResult
    public static func behalte(fundId: UUID, in analyse: inout Analyse) -> Int {
        guard let fund = analyse.funde.first(where: { $0.id == fundId }) else { return 0 }
        let gesucht = fund.text.lowercased()
        var betroffen = 0
        for index in analyse.funde.indices
        where analyse.funde[index].text.lowercased() == gesucht && analyse.funde[index].verworfen {
            analyse.funde[index].verworfen = false
            if analyse.funde[index].eintragId == nil {
                analyse.unbekannte[analyse.funde[index].platzhalter] = analyse.funde[index].text
            }
            betroffen += 1
        }
        return betroffen
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
