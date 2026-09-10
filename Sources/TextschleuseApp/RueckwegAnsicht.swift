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

    private(set) var ergebnis: RueckwegErgebnis
    private var woerterbuch: Woerterbuch
    private let unbekannte: [String: String]

    private var auswahl = 0
    private var bereiche: [UUID: NSRange] = [:]

    private let kopfzeile = NSTextField(labelWithString: "")
    private let warnzeile = NSTextField(labelWithString: "")
    private let flaeche = Textflaeche.bauen()
    private var textAnsicht: ChiptextAnsicht { flaeche.text }
    private var rollflaeche: NSScrollView { flaeche.rolle }
    private let liste = Fundstellenliste()
    private lazy var suche = Textsuche(ziel: textAnsicht)
    private let knopfleiste = NSStackView()
    private let fusszeile = NSTextField(labelWithString: "")
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

        liste.translatesAutoresizingMaskIntoConstraints = false
        liste.beiAuswahl = { [weak self] kennung in
            self?.waehleFund(kennung)
        }

        suche.translatesAutoresizingMaskIntoConstraints = false
        suche.beimSchliessen = { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.textAnsicht)
        }

        knopfleiste.orientation = .horizontal
        knopfleiste.spacing = 6
        let zuordnen = NSButton(title: "Zu Eintrag zuordnen …", target: self, action: #selector(zuordnen))
        zuordnen.toolTip = "Sagt einmal, wer hinter diesem Platzhalter steckt. Gilt danach dauerhaft."
        let anlegen = NSButton(title: "Als neuen Eintrag …", target: self, action: #selector(neuAnlegen))
        anlegen.toolTip = "Legt den Klartext im Wörterbuch an und bindet den Platzhalter daran."
        let neu = NSButton(title: "Neuer Text (⌘N)", target: self, action: #selector(neuEinlesen))
        neu.toolTip = "Liest, was jetzt in der Zwischenablage liegt."
        let kopieren = NSButton(title: "Ergebnis kopieren", target: self, action: #selector(aktionKopieren(_:)))
        kopieren.keyEquivalent = "\r"
        kopieren.toolTip = "⏎ macht dasselbe"
        kopieren.bezelStyle = .rounded
        knopfleiste.addArrangedSubview(kopieren)

        let zurueckKnopf = NSButton(title: "↑", target: self, action: #selector(aktionVorigeFundstelle(_:)))
        zurueckKnopf.toolTip = "Voriger Platzhalter (↑)"
        let vorKnopf = NSButton(title: "↓", target: self, action: #selector(aktionNaechsteFundstelle(_:)))
        vorKnopf.toolTip = "Nächster Platzhalter (↓)"
        let suchKnopf = NSButton(title: "Suchen", target: self, action: #selector(aktionSuchen(_:)))
        suchKnopf.toolTip = "Im Text suchen (⌘F)"
        ignorierKnopf = NSButton(title: "Ignorieren (⌫)", target: self, action: #selector(aktionIgnorieren(_:)))
        ignorierKnopf.toolTip = "Diesen Platzhalter beiseitelegen. Er bleibt im Text stehen, "
            + "zählt aber nicht mehr als offener Punkt. Gilt für alle Stellen mit demselben Namen."

        for knopf in [zurueckKnopf, vorKnopf, suchKnopf, zuordnen, anlegen, ignorierKnopf, neu] {
            knopf.bezelStyle = .rounded
            knopf.controlSize = .small
            knopfleiste.addArrangedSubview(knopf)
        }

        meldung.font = .systemFont(ofSize: 11)
        meldung.textColor = .systemRed
        meldung.isHidden = true
        knopfleiste.addArrangedSubview(meldung)

        fusszeile.font = .systemFont(ofSize: 11)
        fusszeile.textColor = .secondaryLabelColor
        fusszeile.stringValue = "⏎ Kopieren · ↑ ↓ Platzhalter · ⌫ Ignorieren · ⌘F Suchen · "
            + "⌘N Neuer Text · ⎋ Abbrechen. Was rot ist, kennt das Wörterbuch nicht — unten "
            + "zuordnen, dann geht es dauerhaft auf, oder mit ⌫ beiseitelegen."

        let mitte = NSStackView(views: [rollflaeche, liste])
        mitte.orientation = .horizontal
        mitte.spacing = 12
        mitte.distribution = .fill
        mitte.translatesAutoresizingMaskIntoConstraints = false

        let stapel = NSStackView(views: [kopfzeile, warnzeile, suche, mitte, knopfleiste, fusszeile])
        stapel.orientation = .vertical
        stapel.spacing = 10
        stapel.alignment = .leading
        stapel.edgeInsets = NSEdgeInsets(top: 28, left: 18, bottom: 16, right: 18)
        stapel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stapel)
        NSLayoutConstraint.activate([
            stapel.topAnchor.constraint(equalTo: topAnchor),
            stapel.leadingAnchor.constraint(equalTo: leadingAnchor),
            stapel.trailingAnchor.constraint(equalTo: trailingAnchor),
            stapel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        for zeile in [kopfzeile, warnzeile, fusszeile] {
            zeile.setContentHuggingPriority(.required, for: .vertical)
        }
        knopfleiste.setContentHuggingPriority(.required, for: .vertical)
        suche.setContentHuggingPriority(.required, for: .vertical)
        mitte.setContentHuggingPriority(.defaultLow, for: .vertical)
        mitte.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        NSLayoutConstraint.activate([
            mitte.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -36),
            mitte.heightAnchor.constraint(greaterThanOrEqualToConstant: 260),
            liste.widthAnchor.constraint(equalToConstant: 260),
            suche.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -36),
        ])
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
        for ansicht in knopfleiste.arrangedSubviews {
            guard let knopf = ansicht as? NSButton else { continue }
            if knopf.title.hasPrefix("Zu Eintrag") {
                knopf.isEnabled = offen && !woerterbuch.eintraege.isEmpty
            } else if knopf.title.hasPrefix("Als neuen") {
                knopf.isEnabled = offen
            }
        }
        // Aufgelöste Platzhalter lassen sich nicht beiseitelegen — sie sind
        // ja schon beantwortet.
        ignorierKnopf.isEnabled = offen
        ignorierKnopf.title = fund?.ignoriert == true ? "Wieder beachten (⌫)" : "Ignorieren (⌫)"
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
            kopfzeile.stringValue = "In der Zwischenablage steht kein Text"
            warnzeile.stringValue = "Kopiere die KI-Antwort und drücke ⌘N."
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

    /// Der zurückgedrehte Text mit den eingesetzten Namen hervorgehoben, damit
    /// du siehst, wo etwas passiert ist.
    private func aufbereiteterText(ausgewaehlt: UUID?) -> Chiptext.Ergebnis {
        let fertig = NSMutableAttributedString(
            string: ergebnis.ergebnis,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor,
            ]
        )

        // Von vorn durchgehen und die eingesetzten Stellen einfärben. Der
        // Versatz ergibt sich aus der Längendifferenz der schon ersetzten.
        var stellen: [UUID: NSRange] = [:]
        var versatz = 0
        for fund in ergebnis.funde.sorted(by: { $0.bereich.location < $1.bereich.location }) {
            let laenge = (fund.klartext ?? fund.geschrieben).count
            let bereich = NSRange(location: fund.bereich.location + versatz, length: laenge)
            versatz += laenge - fund.bereich.length
            guard bereich.location >= 0, NSMaxRange(bereich) <= fertig.length else { continue }

            let farbe: NSColor = fund.istAufloesbar ? .systemGreen : .systemRed
            fertig.addAttributes([
                .backgroundColor: farbe.withAlphaComponent(fund.id == ausgewaehlt ? 0.34 : 0.16),
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            ], range: bereich)
            if fund.id == ausgewaehlt {
                fertig.addAttributes([
                    .underlineStyle: NSUnderlineStyle.thick.rawValue,
                    .underlineColor: farbe,
                ], range: bereich)
            }
            stellen[fund.id] = bereich
        }
        return Chiptext.Ergebnis(text: fertig, bereiche: stellen)
    }

    // MARK: Tastatur

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
                return false
            }
        }

        switch ereignis.keyCode {
        case 36, 76:
            beiUebernahme?(ergebnis.ergebnis)
            return true
        case 53:
            beiAbbruch?()
            return true
        case 126:
            waehle(auswahl - 1)
            return true
        case 125:
            waehle(auswahl + 1)
            return true
        case 51, 117:
            // ⌫ und ⌦, wie im Schützen-Modus das Verwerfen.
            aktionIgnorieren(nil)
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

        ergebnis = Rueckweg.analysiere(text, woerterbuch: woerterbuch, unbekannte: unbekannte)
        auswahl = 0
        meldung.isHidden = true
        aktualisiere()
    }
}
