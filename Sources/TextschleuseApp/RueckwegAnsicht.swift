import AppKit
import TextschleuseCore

/// Die Arbeitsfläche für den Rückweg. Gleicher Aufbau wie beim Schützen:
/// links der Text, rechts die Liste. Nur andersherum — grün heißt auflösbar,
/// rot heißt, das Wörterbuch kennt den Platzhalter nicht.
final class RueckwegAnsicht: NSView, NSUserInterfaceValidations {

    var beiUebernahme: ((String) -> Void)?
    var beiAbbruch: (() -> Void)?

    /// Läuft, wenn ein Deckname zugeordnet wurde. Die Änderung muss nach oben
    /// und in die Datei, sonst ist sie beim nächsten Text wieder weg.
    var beiWoerterbuchAenderung: ((Woerterbuch) -> Void)?

    /// Läuft nach jeder Änderung am Text, damit der Verlauf mitschreibt.
    var beiAenderung: ((RueckwegErgebnis) -> Void)?

    private(set) var ergebnis: RueckwegErgebnis
    private var woerterbuch: Woerterbuch
    private var unbekannte: [String: String]
    /// Sammelt Tastenanschläge, damit nicht bei jedem Buchstaben neu
    /// gesucht wird.
    private var nachdenkpause: Timer?
    private var tastenKnopf = NSButton()

    private var auswahl = 0
    private var bereiche: [UUID: NSRange] = [:]

    private let kopfzeile = NSTextField(labelWithString: "")
    private let warnzeile = NSTextField(labelWithString: "")
    private let flaeche = Textflaeche.bauen()
    private var textAnsicht: ChiptextAnsicht { flaeche.text }
    private var rollflaeche: NSScrollView { flaeche.rolle }
    private let liste = Fundstellenliste()
    private lazy var suche = Textsuche(ziel: textAnsicht)
    /// Zwei beschriftete Reihen unter dem Text, wie beim Schützen: erst, was
    /// mit dem Platzhalter geschehen soll, dann die Werkzeuge für den Text.
    private let platzhalterLeiste = Fliessleiste()
    private let werkzeugLeiste = Fliessleiste()
    private var zuordnenKnopf = NSButton()
    private var anlegenKnopf = NSButton()
    private let fusszeile = NSTextField(wrappingLabelWithString: "")
    private let meldung = NSTextField(labelWithString: "")
    /// Wechselt zwischen „Ignorieren" und „Wieder beachten", je nachdem, was
    /// gerade ausgewählt ist.
    private var ignorierKnopf = NSButton()

    init(
        ergebnis: RueckwegErgebnis,
        woerterbuch: Woerterbuch = Woerterbuch(),
        unbekannte: [String: String] = [:]
    ) {
        self.ergebnis = ergebnis
        self.woerterbuch = woerterbuch
        self.unbekannte = unbekannte
        super.init(frame: NSRect(x: 0, y: 0, width: 960, height: 600))
        baueOberflaeche()
        aktualisiere()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }

    func zuordnenFuerPruefung(zu eintragId: UUID) -> Bool {
        guard let fund = aktuellerFund, !fund.istAufloesbar else { return false }
        do {
            try woerterbuch.ordneDecknameZu(fund.normal, zu: eintragId)
            uebernimmWoerterbuch("")
            return true
        } catch {
            return false
        }
    }
    func waehleFundFuerPruefung(_ index: Int) { auswahl = index; aktualisiere() }
    func offeneFuerPruefung() -> Int { ergebnis.offen.count }

    func setze(ergebnis neues: RueckwegErgebnis) {
        ergebnis = neues
        auswahl = 0
        meldung.isHidden = true
        textAnsicht.setSelectedRange(NSRange(location: 0, length: 0))
        aktualisiere()
        textAnsicht.scroll(NSPoint(x: 0, y: 0))
    }

    /// Ein neuer Text mit dem aktuellen Stand von Wörterbuch und
    /// Sitzungsplatzhaltern.
    func setze(
        ergebnis neues: RueckwegErgebnis,
        woerterbuch buch: Woerterbuch,
        unbekannte neue: [String: String]
    ) {
        woerterbuch = buch
        unbekannte = neue
        setze(ergebnis: neues)
    }

    /// Nimmt ein von außen geändertes Wörterbuch an und löst den Text damit
    /// neu auf — ohne Meldung, das war keine Entscheidung hier im Fenster.
    func setze(woerterbuch buch: Woerterbuch) {
        guard buch.eintraege.count != woerterbuch.eintraege.count
            || buch.alleDecknamen != woerterbuch.alleDecknamen
        else { return }
        woerterbuch = buch
        ergebnis = Rueckweg.analysiere(ergebnis.original, woerterbuch: woerterbuch, unbekannte: unbekannte)
        aktualisiere()
    }

    // MARK: Aufbau

    private func baueOberflaeche() {
        kopfzeile.font = .systemFont(ofSize: 15, weight: .semibold)
        warnzeile.font = .systemFont(ofSize: 12)
        warnzeile.textColor = .secondaryLabelColor
        warnzeile.lineBreakMode = .byTruncatingTail

        textAnsicht.tastenweiche = { [weak self] ereignis in
            self?.verarbeite(ereignis) ?? false
        }
        // Bearbeitbar wie beim Schützen: was dasteht, ist der Text mit den
        // Platzhaltern, die eingesetzten Namen sind nur Anzeige daneben.
        textAnsicht.delegate = self
        textAnsicht.isEditable = true
        textAnsicht.isRichText = false
        textAnsicht.allowsUndo = false
        textAnsicht.font = .systemFont(ofSize: 13)

        tastenKnopf = Knoepfe.knopf(
            "Tastenkürzel", symbol: "keyboard",
            ziel: self, aktion: #selector(zeigeTastenkuerzel),
            hilfe: "Alle Tasten auf einen Blick (⌘/)"
        )
        tastenKnopf.controlSize = .small
        tastenKnopf.font = .systemFont(ofSize: 11)
        let kopfzeileMitHilfe = NSStackView(views: [kopfzeile, NSView(), tastenKnopf])
        kopfzeileMitHilfe.orientation = .horizontal
        kopfzeileMitHilfe.spacing = 8
        kopfzeileMitHilfe.translatesAutoresizingMaskIntoConstraints = false

        liste.translatesAutoresizingMaskIntoConstraints = false
        liste.beiAuswahl = { [weak self] kennung in
            self?.waehleFund(kennung)
        }

        suche.translatesAutoresizingMaskIntoConstraints = false
        suche.beimSchliessen = { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.textAnsicht)
        }

        let fuss = baueFussbereich()

        let mitte = NSStackView(views: [rollflaeche, liste])
        mitte.orientation = .horizontal
        mitte.spacing = 12
        mitte.distribution = .fill
        mitte.translatesAutoresizingMaskIntoConstraints = false

        let stapel = NSStackView(views: [kopfzeileMitHilfe, warnzeile, suche, mitte, fuss])
        stapel.orientation = .vertical
        stapel.spacing = 10
        stapel.alignment = .leading
        stapel.edgeInsets = NSEdgeInsets(top: 28, left: 18, bottom: 14, right: 18)
        stapel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stapel)
        NSLayoutConstraint.activate([
            stapel.topAnchor.constraint(equalTo: topAnchor),
            stapel.leadingAnchor.constraint(equalTo: leadingAnchor),
            stapel.trailingAnchor.constraint(equalTo: trailingAnchor),
            stapel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        for zeile in [kopfzeile, warnzeile] {
            zeile.setContentHuggingPriority(.required, for: .vertical)
        }
        kopfzeileMitHilfe.setContentHuggingPriority(.required, for: .vertical)
        fuss.setContentHuggingPriority(.required, for: .vertical)
        fuss.setContentCompressionResistancePriority(.required, for: .vertical)
        suche.setContentHuggingPriority(.required, for: .vertical)
        mitte.setContentHuggingPriority(.defaultLow, for: .vertical)
        mitte.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        NSLayoutConstraint.activate([
            mitte.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -36),
            mitte.heightAnchor.constraint(greaterThanOrEqualToConstant: 260),
            // 300 statt 260: eine Zufallskennung ist achtzehn Stellen lang.
            liste.widthAnchor.constraint(equalToConstant: 300),
            suche.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -36),
            fuss.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -36),
            kopfzeileMitHilfe.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -36),
        ])
    }

    @objc func zeigeTastenkuerzel() {
        Tastenkuerzel.zeige(ueber: window)
    }

    /// Der Bereich unter dem Text, gebaut wie beim Schützen: Trennlinie,
    /// beschriftete Reihen, Tastenlegende.
    private func baueFussbereich() -> NSView {
        let trennlinie = NSBox()
        trennlinie.boxType = .separator
        trennlinie.translatesAutoresizingMaskIntoConstraints = false

        // Reihe „Platzhalter": vor und zurück, dann die Entscheidungen.
        let zurueckKnopf = Knoepfe.symbolknopf(
            "chevron.up", beschreibung: "Voriger Platzhalter",
            ziel: self, aktion: #selector(aktionVorigeFundstelle(_:)),
            hilfe: "Voriger Platzhalter (↑)"
        )
        let vorKnopf = Knoepfe.symbolknopf(
            "chevron.down", beschreibung: "Nächster Platzhalter",
            ziel: self, aktion: #selector(aktionNaechsteFundstelle(_:)),
            hilfe: "Nächster Platzhalter (↓)"
        )
        zuordnenKnopf = Knoepfe.knopf(
            "Zu Eintrag zuordnen …", symbol: "link",
            ziel: self, aktion: #selector(zuordnen),
            hilfe: "Sagt einmal, wer hinter diesem Platzhalter steckt. Gilt danach dauerhaft."
        )
        anlegenKnopf = Knoepfe.knopf(
            "Als neuen Eintrag …", symbol: "plus.circle",
            ziel: self, aktion: #selector(neuAnlegen),
            hilfe: "Legt den Klartext im Wörterbuch an und bindet den Platzhalter daran."
        )
        ignorierKnopf = Knoepfe.knopf(
            "Ignorieren", symbol: "delete.left",
            ziel: self, aktion: #selector(aktionIgnorieren(_:)),
            hilfe: "Diesen Platzhalter beiseitelegen (⌫). Er bleibt im Text stehen, "
                + "zählt aber nicht mehr als offener Punkt. Gilt für alle Stellen mit demselben Namen."
        )
        platzhalterLeiste.translatesAutoresizingMaskIntoConstraints = false
        platzhalterLeiste.setze([
            zurueckKnopf, vorKnopf, Gruppentrenner(), zuordnenKnopf, anlegenKnopf, ignorierKnopf,
        ])

        meldung.font = .systemFont(ofSize: 12)
        meldung.textColor = .systemRed
        meldung.lineBreakMode = .byTruncatingTail
        meldung.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Reihe „Text": Werkzeuge, rechts das Kopieren als Abschluss.
        let suchKnopf = Knoepfe.knopf(
            "Suchen", symbol: "magnifyingglass",
            ziel: self, aktion: #selector(aktionSuchen(_:)),
            hilfe: "Im Text suchen (⌘F)"
        )
        let neu = Knoepfe.knopf(
            "Neuer Text", symbol: "doc.on.clipboard",
            ziel: self, aktion: #selector(neuEinlesen),
            hilfe: "Liest, was jetzt in der Zwischenablage liegt (⌘N)."
        )
        werkzeugLeiste.translatesAutoresizingMaskIntoConstraints = false
        werkzeugLeiste.setze([suchKnopf, neu])

        let kopieren = Knoepfe.knopf(
            "Ergebnis kopieren", symbol: "lock.open.fill",
            ziel: self, aktion: #selector(aktionKopieren(_:)),
            hilfe: "⌘⏎ macht dasselbe, ⏎ in der Liste auch"
        )
        kopieren.keyEquivalent = "\r"
        kopieren.keyEquivalentModifierMask = [.command]
        if #available(macOS 26.0, *) {
            kopieren.tintProminence = .primary
        } else {
            kopieren.bezelColor = .controlAccentColor
        }
        kopieren.setContentHuggingPriority(.required, for: .horizontal)
        kopieren.setContentCompressionResistancePriority(.required, for: .horizontal)

        let textZeile = NSStackView(views: [werkzeugLeiste, kopieren])
        textZeile.orientation = .horizontal
        textZeile.spacing = 16
        textZeile.alignment = .firstBaseline
        textZeile.translatesAutoresizingMaskIntoConstraints = false
        werkzeugLeiste.setContentHuggingPriority(.defaultLow, for: .horizontal)

        fusszeile.font = .systemFont(ofSize: 12)
        fusszeile.textColor = .tertiaryLabelColor
        fusszeile.preferredMaxLayoutWidth = 900
        fusszeile.stringValue = "⌘⏎ kopiert · ↑ ↓ Platzhalter und ⌫ ignoriert in der Liste · "
            + "⇥ wechselt zwischen Text und Liste · ⎋ bricht ab. "
            + "Was rot ist, kennt das Wörterbuch nicht: zuordnen, dann geht es dauerhaft auf."

        let etikettBreite: CGFloat = 84
        var reihen: [NSStackView] = []
        for (name, inhalt) in [
            ("Platzhalter", platzhalterLeiste as NSView),
            ("", meldung),
            ("Text", textZeile),
        ] {
            let etikett = Knoepfe.etikett(name)
            let reihe = NSStackView(views: [etikett, inhalt])
            reihe.orientation = .horizontal
            reihe.spacing = 12
            reihe.alignment = .firstBaseline
            reihe.translatesAutoresizingMaskIntoConstraints = false
            etikett.widthAnchor.constraint(equalToConstant: etikettBreite).isActive = true
            inhalt.setContentHuggingPriority(.defaultLow, for: .horizontal)
            reihen.append(reihe)
        }

        let fuss = NSStackView(views: [trennlinie] + reihen + [fusszeile])
        fuss.orientation = .vertical
        fuss.spacing = 10
        fuss.alignment = .leading
        fuss.setCustomSpacing(14, after: trennlinie)
        fuss.setCustomSpacing(4, after: reihen[0])
        fuss.setCustomSpacing(14, after: reihen[2])
        fuss.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate(
            [trennlinie.widthAnchor.constraint(equalTo: fuss.widthAnchor),
             fusszeile.widthAnchor.constraint(equalTo: fuss.widthAnchor)]
            + reihen.map { $0.widthAnchor.constraint(equalTo: fuss.widthAnchor) }
        )
        return fuss
    }

    // MARK: Darstellung

    private func aktualisiere() {
        let sortiert = ergebnis.funde.sorted { $0.bereich.location < $1.bereich.location }
        auswahl = sortiert.isEmpty ? 0 : min(auswahl, sortiert.count - 1)
        let gewaehlt = sortiert.indices.contains(auswahl) ? sortiert[auswahl].id : nil

        let aufbau = aufbereiteterText(ausgewaehlt: gewaehlt)
        bereiche = aufbau.bereiche
        textAnsicht.textStorage?.setAttributedString(aufbau.text)

        beschrifteKopf()
        liste.zeige(
            sortiert.map(listenzeile),
            ausgewaehlt: gewaehlt,
            leertext: ergebnis.original.isEmpty
                ? "Kein Text zum Prüfen."
                : "Keine Platzhalter im Text.\n\nMit ⏎ kopierst du den Text unverändert."
        )

        if let gewaehlt, let bereich = bereiche[gewaehlt] {
            textAnsicht.scrollRangeToVisible(bereich)
        }
        suche.aktualisiere()
        aktualisiereKnoepfe()
    }

    /// Zuordnen geht nur bei einem Platzhalter, der noch offen ist. Bei den
    /// aufgelösten gibt es nichts zu entscheiden.
    private func aktualisiereKnoepfe() {
        let fund = aktuellerFund
        let offen = fund?.istAufloesbar == false
        zuordnenKnopf.isEnabled = offen && !woerterbuch.eintraege.isEmpty
        anlegenKnopf.isEnabled = offen
        // Aufgelöste Platzhalter lassen sich nicht beiseitelegen — sie sind
        // ja schon beantwortet.
        ignorierKnopf.isEnabled = offen
        ignorierKnopf.title = fund?.ignoriert == true ? "Wieder beachten" : "Ignorieren"
        Knoepfe.setze(symbol: fund?.ignoriert == true ? "eye" : "delete.left", auf: ignorierKnopf)
    }

    /// Legt den ausgewählten Platzhalter beiseite oder holt ihn zurück.
    @objc func aktionIgnorieren(_ absender: Any?) {
        guard let fund = aktuellerFund, !fund.istAufloesbar else { return }
        let betroffen = fund.ignoriert
            ? ergebnis.beachteWieder(fundId: fund.id)
            : ergebnis.ignoriere(fundId: fund.id)
        aktualisiere()
        guard betroffen > 0 else { return }
        meldung.textColor = .secondaryLabelColor
        meldung.stringValue = fund.ignoriert
            ? "\(fund.normal) zählt wieder als offener Punkt."
            : (betroffen > 1
                ? "\(fund.normal) bleibt an allen \(betroffen) Stellen stehen."
                : "\(fund.normal) bleibt stehen.")
        meldung.isHidden = false
    }

    private var aktuellerFund: PlatzhalterFund? {
        let sortiert = ergebnis.funde.sorted { $0.bereich.location < $1.bereich.location }
        guard sortiert.indices.contains(auswahl) else { return nil }
        return sortiert[auswahl]
    }

    /// Fokus in die Platzhalterliste, damit die Pfeiltasten sofort greifen.
    @discardableResult
    func fokussiereFundstellen() -> Bool {
        if liste.fokussiere() { return true }
        window?.makeFirstResponder(textAnsicht)
        return false
    }

    // MARK: Tasten und Menü

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with ereignis: NSEvent) {
        if verarbeite(ereignis) { return }
        super.keyDown(with: ereignis)
    }

    @objc func aktionKopieren(_ absender: Any?) { beiUebernahme?(ergebnis.ergebnis) }
    @objc func aktionNeuerText(_ absender: Any?) { neuEinlesen() }
    @objc func aktionSuchen(_ absender: Any?) { suche.oeffne() }
    @objc func aktionNaechsteFundstelle(_ absender: Any?) { waehle(auswahl + 1) }
    @objc func aktionVorigeFundstelle(_ absender: Any?) { waehle(auswahl - 1) }
    @objc func aktionZuordnen(_ absender: Any?) { zuordnen() }
    @objc func aktionNeuerEintrag(_ absender: Any?) { neuAnlegen() }

    func validateUserInterfaceItem(_ eintrag: NSValidatedUserInterfaceItem) -> Bool {
        switch eintrag.action {
        case #selector(aktionZuordnen(_:)):
            return aktuellerFund?.istAufloesbar == false && !woerterbuch.eintraege.isEmpty
        case #selector(aktionNeuerEintrag(_:)), #selector(aktionIgnorieren(_:)):
            return aktuellerFund?.istAufloesbar == false
        case #selector(aktionNaechsteFundstelle(_:)), #selector(aktionVorigeFundstelle(_:)):
            return !ergebnis.funde.isEmpty
        case #selector(aktionKopieren(_:)):
            return !ergebnis.original.isEmpty
        default:
            return true
        }
    }

    // MARK: Zuordnen

    @objc private func zuordnen() {
        guard let fund = aktuellerFund, !fund.istAufloesbar else { return }
        guard let ziel = EintragWaehler.frage(
            woerterbuch: woerterbuch,
            fuer: fund.normal,
            vorschlag: nil
        ) else { return }

        do {
            try woerterbuch.ordneDecknameZu(fund.normal, zu: ziel.id)
            uebernimmWoerterbuch("\(fund.normal) ist jetzt \(ziel.text).")
        } catch {
            meldeFehler(error.localizedDescription)
        }
    }

    @objc private func neuAnlegen() {
        guard let fund = aktuellerFund, !fund.istAufloesbar else { return }
        guard let (text, kategorie) = frageNachEintrag(fuer: fund.normal) else { return }

        do {
            _ = try woerterbuch.anlegen(text: text, kategorie: kategorie, deckname: fund.normal)
            uebernimmWoerterbuch("\(fund.normal) ist jetzt \(text).")
        } catch {
            meldeFehler(error.localizedDescription)
        }
    }

    /// Nach der Zuordnung neu auflösen und die Änderung nach oben melden.
    private func uebernimmWoerterbuch(_ satz: String) {
        beiWoerterbuchAenderung?(woerterbuch)
        ergebnis = Rueckweg.analysiere(
            ergebnis.original,
            woerterbuch: woerterbuch,
            unbekannte: unbekannte
        )
        aktualisiere()
        meldung.textColor = .secondaryLabelColor
        meldung.stringValue = satz
        meldung.isHidden = false
    }

    private func meldeFehler(_ text: String) {
        meldung.textColor = .systemRed
        meldung.stringValue = text
        meldung.isHidden = false
    }

    /// Fragt nach Klartext und Typ für einen neuen Eintrag.
    private func frageNachEintrag(fuer platzhalter: String) -> (String, Kategorie)? {
        let feld = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        feld.placeholderString = "Wer oder was steckt dahinter?"

        let wahl = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 25))
        for kategorie in Kategorie.allCases where kategorie != .unbekannt {
            wahl.addItem(withTitle: kategorie.anzeigename)
            wahl.lastItem?.representedObject = kategorie.rawValue
        }
        // Aus PERSON_3 lässt sich der Typ ablesen; aus UNBEKANNT_3 nicht.
        if let passend = Kategorie.allCases.first(where: { platzhalter.hasPrefix($0.praefix + "_") }),
           passend != .unbekannt {
            wahl.selectItem(withTitle: passend.anzeigename)
        }

        let stapel = NSStackView(views: [feld, wahl])
        stapel.orientation = .vertical
        stapel.spacing = 8
        stapel.alignment = .leading
        stapel.frame = NSRect(x: 0, y: 0, width: 320, height: 60)

        let frage = NSAlert()
        frage.messageText = "Was ist \(platzhalter)?"
        frage.informativeText = "Der Eintrag wandert ins Wörterbuch und behält diesen Platzhalter. "
            + "Damit löst er auch in künftigen Antworten auf."
        frage.accessoryView = stapel
        frage.window.initialFirstResponder = feld
        frage.addButton(withTitle: "Anlegen")
        frage.addButton(withTitle: "Abbrechen")

        guard frage.runModal() == .alertFirstButtonReturn else { return nil }
        let text = feld.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              let roh = wahl.selectedItem?.representedObject as? String,
              let kategorie = Kategorie(rawValue: roh)
        else { return nil }
        return (text, kategorie)
    }

    private func beschrifteKopf() {
        guard !ergebnis.original.isEmpty else {
            kopfzeile.stringValue = "Kein Text zum Zurückdrehen"
            warnzeile.stringValue = "Füge die KI-Antwort hier ein, oder kopiere sie und drücke ⌘N."
            warnzeile.textColor = .secondaryLabelColor
            return
        }
        guard !ergebnis.funde.isEmpty else {
            kopfzeile.stringValue = "Keine Platzhalter gefunden"
            warnzeile.stringValue = "Der Text enthält nichts, was zurückzudrehen wäre."
            warnzeile.textColor = .secondaryLabelColor
            return
        }

        kopfzeile.stringValue = "\(ergebnis.aufgeloest.count) von \(ergebnis.funde.count) Platzhaltern aufgelöst"
        let beiseite = Set(ergebnis.ignorierte.map(\.normal)).count
        let nachsatz = beiseite > 0 ? " \(beiseite) beiseitegelegt." : ""
        if ergebnis.offen.isEmpty {
            warnzeile.stringValue = "Alle Platzhalter sind entschieden." + nachsatz
            warnzeile.textColor = .secondaryLabelColor
        } else {
            let liste = Set(ergebnis.offen.map(\.normal)).sorted().joined(separator: ", ")
            warnzeile.stringValue = "Bleiben stehen, weil das Wörterbuch sie nicht kennt: \(liste)."
                + " ⌫ legt sie beiseite." + nachsatz
            warnzeile.textColor = .systemRed
        }
    }

    private func listenzeile(_ fund: PlatzhalterFund) -> Fundstellenliste.Zeile {
        let status: String
        let farbe: NSColor
        if fund.istAufloesbar {
            status = "wird eingesetzt"
            farbe = .systemGreen
        } else if fund.ignoriert {
            status = "ignoriert, bleibt stehen"
            farbe = .tertiaryLabelColor
        } else {
            status = "unbekannt, bleibt stehen"
            farbe = .systemRed
        }
        return Fundstellenliste.Zeile(
            id: fund.id,
            begriff: fund.klartext ?? fund.geschrieben,
            deckname: fund.normal,
            status: status,
            farbe: farbe,
            abgeschwaecht: !fund.istAufloesbar
        )
    }

    /// Der Text, wie er eingefügt wurde, mit jedem Platzhalter als Chip:
    /// `PERSON_… → Nyström` in Grün, Unbekanntes in Rot ohne Pfeil,
    /// Beiseitegelegtes blass. So bleibt der Text Zeichen für Zeichen
    /// bearbeitbar, und man sieht trotzdem, was eingesetzt wird.
    private func aufbereiteterText(ausgewaehlt: UUID?) -> Chiptext.Ergebnis {
        let chips = ergebnis.funde.map { fund -> Chiptext.Chip in
            let farbe: NSColor = fund.istAufloesbar
                ? .systemGreen
                : (fund.ignoriert ? .tertiaryLabelColor : .systemRed)
            return Chiptext.Chip(
                id: fund.id,
                bereich: fund.bereich,
                text: fund.geschrieben,
                deckname: fund.klartext ?? "",
                farbe: farbe
            )
        }
        return Chiptext.aufbauen(original: ergebnis.original, chips: chips, ausgewaehlt: ausgewaehlt)
    }

    private var textHatFokus: Bool {
        guard let erster = window?.firstResponder else { return false }
        return erster === textAnsicht
    }

    /// Nimmt, was im Textfeld steht, und löst es nach einer kurzen Pause neu
    /// auf. Beiseitegelegte Platzhalter bleiben beiseitegelegt.
    private func pruefeNachTippen() {
        nachdenkpause?.invalidate()
        nachdenkpause = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.pruefeJetzt()
        }
    }

    private func pruefeJetzt() {
        let getippt = Chiptext.originaltext(aus: textAnsicht.attributedString())
        guard getippt != ergebnis.original else { return }
        let marke = Chiptext.originalPosition(
            fuer: textAnsicht.selectedRange().location,
            in: textAnsicht.attributedString()
        )
        let ignoriert = Set(ergebnis.ignorierte.map(\.normal))

        var neu = Rueckweg.analysiere(getippt, woerterbuch: woerterbuch, unbekannte: unbekannte)
        for fund in neu.funde where ignoriert.contains(fund.normal) {
            neu.ignoriere(fundId: fund.id)
        }
        ergebnis = neu
        aktualisiere()
        let stelle = Chiptext.anzeigePosition(fuer: marke, in: textAnsicht.attributedString())
        textAnsicht.setSelectedRange(NSRange(location: stelle, length: 0))
        beiAenderung?(ergebnis)
    }

    func pruefeJetztFuerPruefung() { pruefeJetzt() }
    func setzeTextFuerPruefung(_ text: String) {
        textAnsicht.string = text
        pruefeJetzt()
    }
    func darfAendernFuerPruefung(_ bereich: NSRange) -> Bool {
        textView(textAnsicht, shouldChangeTextIn: bereich, replacementString: "x")
    }

    // MARK: Tastatur

    /// Wie beim Schützen: im Text gehören ⏎, ⌫ und die Pfeile dem Text. In
    /// der Liste wirken sie auf den Platzhalter. ⌥↑ und ⌥↓ gehen überall.
    @discardableResult
    func verarbeite(_ ereignis: NSEvent) -> Bool {
        let zusatz = ereignis.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if zusatz.contains(.command) {
            switch ereignis.charactersIgnoringModifiers?.lowercased() {
            case "n":
                neuEinlesen()
                return true
            case "f":
                suche.oeffne()
                return true
            case "g":
                if zusatz.contains(.shift) { suche.vorheriger() } else { suche.naechster() }
                return true
            default:
                break
            }
            // ⌘C und Konsorten gehören der Textansicht, nur ⌘⏎ nicht.
            if ereignis.keyCode != 36, ereignis.keyCode != 76 { return false }
        }

        switch ereignis.keyCode {
        case 36, 76 where zusatz.contains(.command) || !textHatFokus:
            beiUebernahme?(ergebnis.ergebnis)
            return true
        case 53:
            beiAbbruch?()
            return true
        case 126 where zusatz.contains(.option) || !textHatFokus:
            waehle(auswahl - 1)
            return true
        case 125 where zusatz.contains(.option) || !textHatFokus:
            waehle(auswahl + 1)
            return true
        case 51 where !textHatFokus, 117 where !textHatFokus:
            // ⌫ und ⌦ in der Liste, wie beim Schützen das Verwerfen.
            aktionIgnorieren(nil)
            return true
        case 48:  // Tabulator: zwischen Text und Liste wechseln
            if textHatFokus { fokussiereFundstellen() } else { window?.makeFirstResponder(textAnsicht) }
            return true
        default:
            return false
        }
    }

    private func waehle(_ index: Int) {
        guard !ergebnis.funde.isEmpty else { return }
        auswahl = (index + ergebnis.funde.count) % ergebnis.funde.count
        aktualisiere()
    }

    private func waehleFund(_ kennung: UUID) {
        let sortiert = ergebnis.funde.sorted { $0.bereich.location < $1.bereich.location }
        guard let index = sortiert.firstIndex(where: { $0.id == kennung }) else { return }
        auswahl = index
        aktualisiere()
    }

    @objc private func neuEinlesen() {
        guard let text = Zwischenablage.lies() else {
            meldung.stringValue = "In der Zwischenablage steht kein Text."
            meldung.isHidden = false
            return
        }
        guard text != ergebnis.original else {
            meldung.stringValue = "In der Zwischenablage liegt derselbe Text wie hier."
            meldung.isHidden = false
            return
        }

        setze(ergebnis: Rueckweg.analysiere(text, woerterbuch: woerterbuch, unbekannte: unbekannte))
        beiAenderung?(ergebnis)
    }
}

extension RueckwegAnsicht: NSTextViewDelegate {

    /// Klick auf einen Chip wählt ihn aus.
    func textView(_ ansicht: NSTextView, clickedOnLink verweis: Any, at zeichen: Int) -> Bool {
        let text = (verweis as? URL)?.absoluteString ?? (verweis as? String) ?? ""
        guard let uuid = UUID(uuidString: text.replacingOccurrences(of: "fund://", with: "")) else { return false }
        waehleFund(uuid)
        return true
    }

    func textView(
        _ ansicht: NSTextView,
        shouldChangeTextIn bereich: NSRange,
        replacementString ersatz: String?
    ) -> Bool {
        guard ansicht === textAnsicht else { return true }
        switch Chiptext.pruefeAenderung(
            bereich: bereich, ersatz: ersatz, in: textAnsicht.attributedString(), chips: bereiche
        ) {
        case .erlaubt:
            return true
        case .verboten:
            meldeFehler("Den eingesetzten Namen kann man hier nicht ändern — im Wörterbuch schon.")
            return false
        case .ausweiten(let ganz):
            Chiptext.loescheSpaeter(ganz, in: textAnsicht)
            return false
        }
    }

    func textDidChange(_ meldung: Notification) {
        guard meldung.object as AnyObject? === textAnsicht else { return }
        pruefeNachTippen()
    }
}
