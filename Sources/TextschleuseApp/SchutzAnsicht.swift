import AppKit
import TextschleuseCore

/// Die Arbeitsfläche zum Schützen: links der Text mit den Fundstellen als
/// Chips, rechts die Liste mit ihrem Stand, unten die Werkzeuge für die
/// ausgewählte Fundstelle.
///
/// Steht als eigene Ansicht da und nicht im Fenster, weil zwei Fenster sie
/// zeigen: das Popup, das der Kurzbefehl aufmacht, und das Hauptfenster für
/// alle, die nicht über die Tastatur arbeiten wollen.
final class SchutzAnsicht: NSView {

    /// Läuft, wenn übernommen wird. `merken` heißt: die noch offenen
    /// Vermutungen wandern ins Wörterbuch.
    var beiUebernahme: ((Analyse, Bool) -> Void)?
    /// Läuft bei Abbruch. Das Popup schließt sich daraufhin; im Hauptfenster
    /// wird der Text nur verworfen.
    var beiAbbruch: (() -> Void)?

    private(set) var analyse: Analyse

    private var auswahl: Int = 0
    private var reihenfolge: [UUID] = []
    private var bereiche: [UUID: NSRange] = [:]

    private let kopfzeile = NSTextField(labelWithString: "")
    private let regelzeile = NSTextField(labelWithString: "")
    private let flaeche = Textflaeche.bauen()
    private var textAnsicht: ChiptextAnsicht { flaeche.text }
    private var rollflaeche: NSScrollView { flaeche.rolle }
    private let liste = Fundstellenliste()
    private lazy var suche = Textsuche(ziel: textAnsicht)

    /// Der Originaltext zum Tippen. Der Chiptext daneben lässt sich nicht
    /// bearbeiten: darin stehen Platzhalter, die im Original nicht vorkommen,
    /// und jede Eingabe würde die Zuordnung zerreißen.
    private let bearbeitung = Textflaeche.bauen()
    private var imBearbeitungsmodus = false
    private var bearbeitenKnopf = NSButton()
    private var mitte = NSStackView()

    private let knopfleiste = NSStackView()
    private let decknameFeld = NSTextField()
    private let decknameEtikett = NSTextField(labelWithString: "Deckname")
    private let merkenHaken = NSButton(checkboxWithTitle: "dauerhaft merken", target: nil, action: nil)
    private let meldung = NSTextField(labelWithString: "")
    private let fusszeile = NSTextField(labelWithString: "")

    init(analyse: Analyse) {
        self.analyse = analyse
        super.init(frame: NSRect(x: 0, y: 0, width: 960, height: 600))
        baueOberflaeche()
        aktualisiere()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }

    /// Wirft den bisherigen Text weg und fängt mit einem neuen an.
    func setze(analyse neue: Analyse) {
        analyse = neue
        auswahl = 0
        imBearbeitungsmodus = false
        zeigeModus()
        textAnsicht.setSelectedRange(NSRange(location: 0, length: 0))
        zeigeMeldung(nil)
        aktualisiere()
        textAnsicht.scroll(NSPoint(x: 0, y: 0))
    }

    // MARK: Aufbau

    private func baueOberflaeche() {
        kopfzeile.font = .systemFont(ofSize: 15, weight: .semibold)
        regelzeile.font = .systemFont(ofSize: 12)
        regelzeile.textColor = .secondaryLabelColor
        regelzeile.lineBreakMode = .byTruncatingTail

        textAnsicht.delegate = self
        textAnsicht.tastenweiche = { [weak self] ereignis in
            self?.verarbeite(ereignis) ?? false
        }
        // Auch beim Tippen am Original muss ⌘E ankommen, sonst käme man aus
        // dem Bearbeitungsmodus nur noch mit der Maus heraus.
        bearbeitung.text.tastenweiche = { [weak self] ereignis in
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
        baueKnoepfe()

        decknameEtikett.font = .systemFont(ofSize: 11)
        decknameEtikett.textColor = .secondaryLabelColor
        decknameFeld.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        decknameFeld.placeholderString = "PERSON_1"
        decknameFeld.target = self
        decknameFeld.action = #selector(decknameUebernehmen)
        decknameFeld.delegate = self
        decknameFeld.toolTip = "Großbuchstaben, Ziffern, Unterstrich. ⏎ übernimmt, ⎋ verwirft."

        merkenHaken.state = .on
        merkenHaken.font = .systemFont(ofSize: 12)
        merkenHaken.toolTip = "Aus heißt: der Deckname gilt nur für diesen Text."

        meldung.font = .systemFont(ofSize: 11)
        meldung.textColor = .systemRed
        meldung.lineBreakMode = .byTruncatingTail
        meldung.isHidden = true

        fusszeile.font = .systemFont(ofSize: 11)
        fusszeile.textColor = .secondaryLabelColor
        fusszeile.stringValue = "1–5 Kategorie, dann Deckname tippen und ⏎ · ⏎ im Text Kopieren · "
            + "⌘⏎ Kopieren und alles merken · ↑ ↓ Fundstelle · ⌫ Verwerfen · G Zur Gruppe · "
            + "⌘E Text bearbeiten · ⌘F Suchen · ⌘N Neuer Text · ⎋ Abbrechen"

        bearbeitung.text.isEditable = true
        bearbeitung.text.font = .systemFont(ofSize: 13)
        bearbeitung.text.isRichText = false
        bearbeitung.text.allowsUndo = true
        bearbeitung.rolle.isHidden = true

        // Text und Liste nebeneinander, die Bearbeitungsfläche liegt an der
        // Stelle des Chiptexts und ist normalerweise ausgeblendet.
        mitte = NSStackView(views: [rollflaeche, bearbeitung.rolle, liste])
        mitte.orientation = .horizontal
        mitte.spacing = 12
        mitte.distribution = .fill
        mitte.translatesAutoresizingMaskIntoConstraints = false

        let decknameZeile = NSStackView(views: [decknameEtikett, decknameFeld, merkenHaken, meldung])
        decknameZeile.orientation = .horizontal
        decknameZeile.spacing = 8
        decknameZeile.translatesAutoresizingMaskIntoConstraints = false

        let stapel = NSStackView(views: [
            kopfzeile, regelzeile, suche, mitte, knopfleiste, decknameZeile, fusszeile,
        ])
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

        for zeile in [kopfzeile, regelzeile, fusszeile] {
            zeile.setContentHuggingPriority(.required, for: .vertical)
        }
        for teil in [knopfleiste, decknameZeile, suche] {
            teil.setContentHuggingPriority(.required, for: .vertical)
        }
        mitte.setContentHuggingPriority(.defaultLow, for: .vertical)
        mitte.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        decknameFeld.setContentHuggingPriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            mitte.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -36),
            mitte.heightAnchor.constraint(greaterThanOrEqualToConstant: 260),
            liste.widthAnchor.constraint(equalToConstant: 260),
            bearbeitung.rolle.widthAnchor.constraint(equalTo: rollflaeche.widthAnchor),
            decknameZeile.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -36),
            suche.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -36),
            decknameFeld.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])
    }

    private func baueKnoepfe() {
        knopfleiste.setViews([], in: .leading)
        for (index, kategorie) in Kategorie.schnellwahl.enumerated() {
            let knopf = NSButton(
                title: "\(kategorie.anzeigename) (\(index + 1))",
                target: self,
                action: #selector(kategorieGeklickt(_:))
            )
            knopf.tag = index
            knopf.bezelStyle = .rounded
            knopf.controlSize = .small
            knopf.toolTip = "Taste \(index + 1) macht dasselbe"
            knopfleiste.addArrangedSubview(knopf)
        }

        let verwerfen = NSButton(title: "Verwerfen (⌫)", target: self, action: #selector(verwerfenGeklickt))
        verwerfen.toolTip = "Rücktaste macht dasselbe"
        let gruppe = NSButton(title: "Zur Gruppe (G)", target: self, action: #selector(gruppeGeklickt))
        gruppe.toolTip = "Taste G macht dasselbe"
        let neu = NSButton(title: "Neuer Text (⌘N)", target: self, action: #selector(neuEinlesen))
        neu.toolTip = "Liest, was jetzt in der Zwischenablage liegt. Der bisherige Text wird verworfen."
        bearbeitenKnopf = NSButton(title: "Text bearbeiten (⌘E)", target: self, action: #selector(bearbeitenUmschalten))
        bearbeitenKnopf.toolTip = "Am Originaltext tippen. Danach wird neu geprüft."
        let leeren = NSButton(title: "Leeren", target: self, action: #selector(leeren))
        leeren.toolTip = "Wirft den Text weg. Das Wörterbuch bleibt."
        for knopf in [verwerfen, gruppe, bearbeitenKnopf, leeren, neu] {
            knopf.bezelStyle = .rounded
            knopf.controlSize = .small
            knopfleiste.addArrangedSubview(knopf)
        }
    }

    // MARK: Darstellung

    private func aktualisiere() {
        reihenfolge = analyse.funde
            .filter { !$0.verworfen }
            .sorted { $0.bereich.location < $1.bereich.location }
            .map(\.id)
        auswahl = reihenfolge.isEmpty ? 0 : min(auswahl, reihenfolge.count - 1)

        let gewaehlt = reihenfolge.indices.contains(auswahl) ? reihenfolge[auswahl] : nil
        let aufbau = Chiptext.aufbauen(analyse: analyse, ausgewaehlt: gewaehlt)
        bereiche = aufbau.bereiche
        textAnsicht.textStorage?.setAttributedString(aufbau.text)

        if !imBearbeitungsmodus { beschrifteKopf() }

        liste.zeige(
            analyse.funde.sorted { $0.bereich.location < $1.bereich.location }.map(listenzeile),
            ausgewaehlt: gewaehlt,
            leertext: analyse.original.isEmpty
                ? "Kein Text zum Prüfen."
                : "Nichts erkannt.\n\nMarkiere links im Text, was geschützt werden soll, und drücke 1–5."
        )

        if let gewaehlt, let bereich = bereiche[gewaehlt] {
            textAnsicht.scrollRangeToVisible(bereich)
        }
        // Der Text ist neu aufgebaut, die alten Trefferbereiche zeigen ins Leere.
        suche.aktualisiere()
        aktualisiereWerkzeuge()
    }

    /// Die beiden Zeilen über dem Text. Sie müssen auch dann etwas sagen, wenn
    /// nichts gefunden wurde — sonst steht ein leeres Fenster da und du weißt
    /// nicht, ob die App überhaupt gelaufen ist.
    private func beschrifteKopf() {
        guard !analyse.original.isEmpty else {
            kopfzeile.stringValue = "In der Zwischenablage steht kein Text"
            regelzeile.stringValue = "Kopiere etwas und drücke ⌘N, dann liest die Textschleuse neu ein."
            return
        }

        let gesamt = analyse.aktiveFunde.count
        guard gesamt > 0 else {
            kopfzeile.stringValue = "Nichts gefunden"
            regelzeile.stringValue = "Der Text ginge unverändert raus. Markiere im Text, was geschützt "
                + "werden soll, und drücke 1–5. Mit ⏎ kopierst du ihn so, wie er ist."
            return
        }

        let offen = analyse.ungeprueft.count
        kopfzeile.stringValue = offen == 0
            ? "\(gesamt) Fundstellen, alle geprüft"
            : "\(gesamt - offen) von \(gesamt) geprüft, \(offen) offen"

        let zusammenfassung = analyse.regelZusammenfassung
            .map { "\($0.anzahl) \($0.kategorie.anzeigename)" }
            .joined(separator: ", ")
        let gemerkt = analyse.aktiveFunde.filter { $0.eintragId != nil }.count
        var teile: [String] = []
        if !zusammenfassung.isEmpty { teile.append("Ohne Nachfrage ersetzt: \(zusammenfassung)") }
        teile.append(gemerkt == 1 ? "1 Eintrag im Wörterbuch" : "\(gemerkt) Einträge im Wörterbuch")
        regelzeile.stringValue = teile.joined(separator: " · ") + "."
    }

    private func listenzeile(_ fund: Fund) -> Fundstellenliste.Zeile {
        Fundstellenliste.Zeile(
            id: fund.id,
            begriff: fund.text,
            deckname: fund.verworfen ? "—" : fund.platzhalter,
            status: status(fuer: fund),
            farbe: fund.verworfen ? .tertiaryLabelColor : Chiptext.farbe(fuer: fund),
            abgeschwaecht: fund.verworfen
        )
    }

    /// Der Satz, der in der Liste unter dem Begriff steht. Er beantwortet:
    /// Bleibt das über diesen Text hinaus bestehen?
    private func status(fuer fund: Fund) -> String {
        if fund.verworfen { return "bleibt im Klartext" }
        if fund.eintragId != nil {
            return fund.quelle == .regel || analyse.woerterbuch
                .eintrag(mitId: fund.eintragId!)?.automatischErkannt == true
                ? "gemerkt, automatisch erkannt"
                : "gemerkt"
        }
        if fund.brauchtPruefung { return "offen, bitte prüfen" }
        return "nur dieser Text"
    }

    private func aktualisiereWerkzeuge() {
        guard !imBearbeitungsmodus else { return }
        let fund = aktuellerFund
        for ansicht in knopfleiste.arrangedSubviews {
            guard let knopf = ansicht as? NSButton else { continue }
            if knopf.title.hasPrefix("Zur Gruppe") {
                knopf.isEnabled = fund?.gruppenVorschlag != nil
                if let vorschlag = fund?.gruppenVorschlag,
                   let eintrag = analyse.woerterbuch.eintrag(mitId: vorschlag) {
                    knopf.toolTip = "Als weitere Schreibweise zu \(eintrag.text) (\(eintrag.platzhalter))"
                }
            } else {
                knopf.isEnabled = fund != nil || hatFreieMarkierung
            }
        }

        decknameFeld.isEnabled = fund != nil && !(fund?.verworfen ?? true)
        decknameFeld.stringValue = fund?.verworfen == false ? (fund?.platzhalter ?? "") : ""
    }

    private var aktuellerFund: Fund? {
        guard reihenfolge.indices.contains(auswahl) else { return nil }
        let kennung = reihenfolge[auswahl]
        return analyse.funde.first { $0.id == kennung }
    }

    /// Eine Markierung im Text, die über die ausgewählte Fundstelle
    /// hinausgeht. Nur dann heißt „Person (1)" auch: mach daraus eine Person.
    private var freieMarkierung: NSRange? {
        let anzeige = textAnsicht.selectedRange()
        guard anzeige.length > 0,
              let original = Chiptext.originalBereich(
                fuer: anzeige,
                in: textAnsicht.attributedString()
              )
        else { return nil }
        if let fund = aktuellerFund, fund.bereich == original { return nil }
        return original
    }

    private var hatFreieMarkierung: Bool { freieMarkierung != nil }

    /// Rote Meldung für Fehler. Erfolgsmeldungen setzt `meldeNachtrag`.
    private func zeigeMeldung(_ text: String?) {
        meldung.textColor = .systemRed
        meldung.stringValue = text ?? ""
        meldung.isHidden = text == nil
    }

    // MARK: Tastatur

    /// Wird sowohl vom Fenster als auch von der Textansicht aufgerufen.
    /// Liefert `true`, wenn der Tastendruck erledigt ist.
    @discardableResult
    func verarbeite(_ ereignis: NSEvent) -> Bool {
        // Im Deckname-Feld gehören die Tasten dem Feld.
        if decknameFeld.currentEditor() != nil {
            return false
        }

        // Beim Tippen am Originaltext auch: sonst legt die 1 eine Person an,
        // statt eine Eins zu schreiben. Nur ⌘E und ⎋ kommen durch.
        if imBearbeitungsmodus {
            let zusatz = ereignis.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if zusatz.contains(.command), ereignis.charactersIgnoringModifiers?.lowercased() == "e" {
                bearbeitenUmschalten()
                return true
            }
            if ereignis.keyCode == 53 {
                bearbeitenUmschalten()
                return true
            }
            return false
        }

        let zusatz = ereignis.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if zusatz.contains(.command) {
            switch ereignis.charactersIgnoringModifiers?.lowercased() {
            case "n":
                neuEinlesen()
                return true
            case "e":
                bearbeitenUmschalten()
                return true
            case "f":
                guard !imBearbeitungsmodus else { return false }
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
        case 36, 76:  // Return, Enter
            uebernehmen(merken: zusatz.contains(.command))
            return true
        case 53:  // Escape
            abbrechen()
            return true
        case 126:  // Pfeil hoch
            waehle(auswahl - 1)
            return true
        case 125:  // Pfeil runter
            waehle(auswahl + 1)
            return true
        case 51, 117:  // Rücktaste, Entfernen
            verwerfeAktuellen()
            return true
        default:
            break
        }

        guard let zeichen = ereignis.charactersIgnoringModifiers?.lowercased() else { return false }
        if let ziffer = Int(zeichen), (1...Kategorie.schnellwahl.count).contains(ziffer) {
            setzeKategorie(Kategorie.schnellwahl[ziffer - 1])
            return true
        }
        if zeichen == "g" {
            gruppeUebernehmen()
            return true
        }
        return false
    }

    private func waehle(_ index: Int) {
        guard !reihenfolge.isEmpty else { return }
        auswahl = (index + reihenfolge.count) % reihenfolge.count
        textAnsicht.setSelectedRange(NSRange(location: 0, length: 0))
        zeigeMeldung(nil)
        aktualisiere()
    }

    private func waehleFund(_ kennung: UUID) {
        guard let index = reihenfolge.firstIndex(of: kennung) else { return }
        auswahl = index
        zeigeMeldung(nil)
        aktualisiere()
    }

    // MARK: Aktionen

    @objc private func kategorieGeklickt(_ absender: NSButton) {
        guard Kategorie.schnellwahl.indices.contains(absender.tag) else { return }
        setzeKategorie(Kategorie.schnellwahl[absender.tag])
    }

    @objc private func verwerfenGeklickt() { verwerfeAktuellen() }

    @objc private func gruppeGeklickt() { gruppeUebernehmen() }

    /// Eine Kategorie zuweisen. Liegt eine eigene Markierung im Text, gilt sie;
    /// sonst die ausgewählte Fundstelle.
    private func setzeKategorie(_ kategorie: Kategorie) {
        zeigeMeldung(nil)

        let vorher = analyse.aktiveFunde.count

        if let bereich = freieMarkierung {
            let merken = merkenHaken.state == .on
            guard let neue = Schleuse.markiere(
                bereich: bereich,
                als: kategorie,
                merken: merken,
                in: &analyse
            ) else {
                zeigeMeldung("Da ist nichts, was sich schützen ließe.")
                return
            }
            textAnsicht.setSelectedRange(NSRange(location: 0, length: 0))
            aktualisiere()
            waehleFund(neue)
            meldeNachtrag(vorher: vorher, merken: merken)
            uebernimmDecknamen()
            return
        }

        guard let fund = aktuellerFund else { return }
        let merken = merkenHaken.state == .on
        Schleuse.bestaetige(fundId: fund.id, als: kategorie, in: &analyse, merken: merken)
        aktualisiere()
        meldeNachtrag(vorher: vorher, merken: merken)
        uebernimmDecknamen()
    }

    /// Setzt den Schreibcursor ins Deckname-Feld und markiert den
    /// vorgeschlagenen Namen.
    ///
    /// Direkt nach der Zuweisung ist der Moment, in dem man weiß, wie das Ding
    /// heißen soll. Der markierte Vorschlag heißt: tippen überschreibt ihn,
    /// ⏎ übernimmt, und wem `PERSON_3` reicht, der drückt einfach ⏎.
    private func uebernimmDecknamen() {
        guard aktuellerFund != nil else { return }
        window?.makeFirstResponder(decknameFeld)
        decknameFeld.currentEditor()?.selectAll(nil)
    }

    /// Sagt, was gerade passiert ist. Ohne diese Zeile merkst du nicht, dass
    /// derselbe Begriff noch dreimal weiter unten im Text stand.
    private func meldeNachtrag(vorher: Int, merken: Bool) {
        let dazu = analyse.aktiveFunde.count - vorher - 1
        var teile: [String] = []
        if dazu > 0 {
            teile.append(dazu == 1
                ? "eine weitere Stelle im Text mitgeschützt"
                : "\(dazu) weitere Stellen im Text mitgeschützt")
        }
        teile.append(merken ? "ins Wörterbuch übernommen" : "gilt nur für diesen Text")

        meldung.textColor = .secondaryLabelColor
        meldung.stringValue = teile.joined(separator: ", ").prefix(1).uppercased()
            + teile.joined(separator: ", ").dropFirst() + "."
        meldung.isHidden = false
    }

    private func gruppeUebernehmen() {
        guard let fund = aktuellerFund, let ziel = fund.gruppenVorschlag else { return }
        Schleuse.alsAliasZuordnen(fundId: fund.id, zu: ziel, in: &analyse)
        weiterZurNaechstenLuecke()
    }

    private func verwerfeAktuellen() {
        guard let fund = aktuellerFund else { return }
        Schleuse.verwerfe(fundId: fund.id, in: &analyse)
        aktualisiere()
    }

    // MARK: Für den Selbsttest

    func bearbeitenUmschaltenFuerPruefung() { bearbeitenUmschalten() }
    func leerenFuerPruefung() { leeren() }
    func setzeBearbeitungstextFuerPruefung(_ text: String) { bearbeitung.text.string = text }

    // MARK: Bearbeiten

    /// Schaltet zwischen Chiptext und Originaltext um. Beim Zurückschalten
    /// wird neu geprüft; das Wörterbuch bleibt, was schon gemerkt ist, greift
    /// also sofort wieder.
    @objc private func bearbeitenUmschalten() {
        if imBearbeitungsmodus {
            let getippt = bearbeitung.text.string
            imBearbeitungsmodus = false
            analyse = Schleuse.analysiere(getippt, woerterbuch: analyse.woerterbuch)
            auswahl = 0
            zeigeModus()
            aktualisiere()
            window?.makeFirstResponder(textAnsicht)
        } else {
            bearbeitung.text.string = analyse.original
            imBearbeitungsmodus = true
            zeigeModus()
            window?.makeFirstResponder(bearbeitung.text)
            zeigeMeldung(nil)
        }
    }

    /// Wirft den Text weg und lässt dich gleich tippen. Ohne das müsste man
    /// erst irgendwas anderes kopieren, um den alten Text loszuwerden.
    @objc private func leeren() {
        analyse = Schleuse.analysiere("", woerterbuch: analyse.woerterbuch)
        auswahl = 0
        bearbeitung.text.string = ""
        imBearbeitungsmodus = true
        zeigeModus()
        aktualisiere()
        window?.makeFirstResponder(bearbeitung.text)
    }

    private func zeigeModus() {
        rollflaeche.isHidden = imBearbeitungsmodus
        bearbeitung.rolle.isHidden = !imBearbeitungsmodus
        liste.isHidden = imBearbeitungsmodus
        suche.isHidden = true
        bearbeitenKnopf.title = imBearbeitungsmodus ? "Fertig, prüfen (⌘E)" : "Text bearbeiten (⌘E)"

        for ansicht in knopfleiste.arrangedSubviews {
            guard let knopf = ansicht as? NSButton, knopf !== bearbeitenKnopf else { continue }
            // Beim Tippen gibt es keine Fundstelle, auf die sich etwas
            // beziehen könnte.
            if !knopf.title.hasPrefix("Leeren"), !knopf.title.hasPrefix("Neuer Text") {
                knopf.isEnabled = !imBearbeitungsmodus
            }
        }
        decknameFeld.isEnabled = !imBearbeitungsmodus && decknameFeld.isEnabled

        if imBearbeitungsmodus {
            kopfzeile.stringValue = "Originaltext bearbeiten"
            regelzeile.stringValue = "Tippe, füge ein oder lösche. ⌘E prüft den Text danach neu."
        }
    }

    /// Holt sich, was jetzt in der Zwischenablage liegt, und fängt damit von
    /// vorn an. Das Wörterbuch bleibt, alles andere am alten Text ist weg.
    @objc private func neuEinlesen() {
        guard let text = Zwischenablage.lies() else {
            zeigeMeldung("In der Zwischenablage steht kein Text.")
            return
        }
        guard text != analyse.original else {
            zeigeMeldung("In der Zwischenablage liegt derselbe Text wie hier.")
            return
        }

        analyse = Schleuse.analysiere(text, woerterbuch: analyse.woerterbuch)
        auswahl = 0
        textAnsicht.setSelectedRange(NSRange(location: 0, length: 0))
        zeigeMeldung(nil)
        aktualisiere()
        textAnsicht.scroll(NSPoint(x: 0, y: 0))
    }

    /// ⏎ im Deckname-Feld: übernehmen und weiter zur nächsten offenen Stelle.
    @objc private func decknameUebernehmen() {
        guard let fund = aktuellerFund else { return }
        let eingabe = decknameFeld.stringValue

        if eingabe.uppercased() != fund.platzhalter.uppercased() {
            do {
                try Schleuse.benenneUm(fundId: fund.id, auf: eingabe, in: &analyse)
                zeigeMeldung(nil)
                aktualisiere()
            } catch {
                // Im Feld bleiben: der Name ist noch nicht gültig, und wer
                // jetzt rausspringt, verliert das Getippte aus den Augen.
                zeigeMeldung(error.localizedDescription)
                decknameFeld.currentEditor()?.selectAll(nil)
                return
            }
        }

        window?.makeFirstResponder(textAnsicht)
        weiterZurNaechstenLuecke()
    }

    /// ⎋ im Deckname-Feld verwirft nur das Getippte. Das Popup bleibt offen —
    /// sonst wäre ein Vertipper die teuerste Taste im Fenster.
    private func decknameAbbrechen() {
        decknameFeld.stringValue = aktuellerFund?.platzhalter ?? ""
        zeigeMeldung(nil)
        window?.makeFirstResponder(textAnsicht)
    }

    /// Nach einer Entscheidung zur nächsten offenen Vermutung springen. Wenn
    /// keine mehr da ist, bleibt die Auswahl stehen.
    private func weiterZurNaechstenLuecke() {
        aktualisiere()
        let offene = analyse.funde
            .filter(\.brauchtPruefung)
            .sorted { $0.bereich.location < $1.bereich.location }
        if let naechste = offene.first, let index = reihenfolge.firstIndex(of: naechste.id) {
            auswahl = index
            aktualisiere()
        }
    }

    func uebernehmen(merken: Bool) {
        beiUebernahme?(analyse, merken)
    }

    func abbrechen() {
        beiAbbruch?()
    }
}

extension SchutzAnsicht: NSTextFieldDelegate {

    /// Fängt ⎋ im Deckname-Feld ab, bevor es beim Fenster landet und das
    /// ganze Popup schließt.
    func control(
        _ steuerelement: NSControl,
        textView: NSTextView,
        doCommandBy befehl: Selector
    ) -> Bool {
        guard steuerelement === decknameFeld, befehl == #selector(NSResponder.cancelOperation(_:)) else {
            return false
        }
        decknameAbbrechen()
        return true
    }
}

extension SchutzAnsicht: NSTextViewDelegate {

    /// Klick auf einen Chip wählt ihn aus. Die Chips tragen dafür eine
    /// `fund://`-Adresse als unsichtbaren Verweis.
    func textView(_ ansicht: NSTextView, clickedOnLink verweis: Any, at zeichen: Int) -> Bool {
        let text: String
        if let adresse = verweis as? URL {
            text = adresse.absoluteString
        } else if let zeichenkette = verweis as? String {
            text = zeichenkette
        } else {
            return false
        }
        guard let uuid = UUID(uuidString: text.replacingOccurrences(of: "fund://", with: "")),
              reihenfolge.contains(uuid)
        else { return false }
        waehleFund(uuid)
        return true
    }

    /// Sobald du im Text markierst, ändert sich, was die Kategorieknöpfe tun.
    func textViewDidChangeSelection(_ meldung: Notification) {
        // Das Feldeditor-Textview des Deckname-Felds meldet sich hier auch.
        guard meldung.object as AnyObject? === textAnsicht else { return }
        aktualisiereWerkzeuge()
        if hatFreieMarkierung {
            zeigeMeldung(nil)
            kopfzeile.stringValue = merkenHaken.state == .on
                ? "Markierung: Taste 1–5 legt sie als neuen Eintrag an"
                : "Markierung: Taste 1–5 schützt sie nur in diesem Text"
        } else {
            beschrifteKopf()
        }
    }
}
