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

    /// Zeigt statt des Originaltexts, was tatsächlich rausgeht — mit
    /// eingesetzten Platzhaltern. Nur zum Ansehen.
    private var inVorschau = false
    private var vorschauKnopf = NSButton()
    /// Sammelt Tastenanschläge, damit nicht bei jedem Buchstaben der ganze
    /// Text neu durchsucht wird.
    private var nachdenkpause: Timer?
    private var mitte = NSStackView()

    private let knopfleiste = NSStackView()
    private let originalFeld = NSTextField()
    private let originalEtikett = NSTextField(labelWithString: "Original")
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
        inVorschau = false
        textAnsicht.isEditable = true
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

        originalEtikett.font = .systemFont(ofSize: 11)
        originalEtikett.textColor = .secondaryLabelColor
        originalFeld.font = .systemFont(ofSize: 12)
        originalFeld.placeholderString = "so steht es im Text"
        originalFeld.target = self
        originalFeld.action = #selector(originalUebernehmen)
        originalFeld.delegate = self
        originalFeld.toolTip = "Korrigiert, was an dieser Stelle im Text steht. ⏎ übernimmt, ⎋ verwirft."

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

        // Der Text ist direkt bearbeitbar. Was dasteht, ist der Originaltext;
        // die Fundstellen sind nur eingefärbt, es wird nichts dazwischen
        // geschoben. Nur so kann man tippen, ohne die Zuordnung zu zerreißen.
        textAnsicht.isEditable = true
        textAnsicht.isRichText = false
        textAnsicht.allowsUndo = true
        textAnsicht.font = .systemFont(ofSize: 13)

        mitte = NSStackView(views: [rollflaeche, liste])
        mitte.orientation = .horizontal
        mitte.spacing = 12
        mitte.distribution = .fill
        mitte.translatesAutoresizingMaskIntoConstraints = false

        let decknameZeile = NSStackView(views: [
            originalEtikett, originalFeld, decknameEtikett, decknameFeld, merkenHaken, meldung,
        ])
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
        originalFeld.setContentHuggingPriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            mitte.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -36),
            mitte.heightAnchor.constraint(greaterThanOrEqualToConstant: 260),
            liste.widthAnchor.constraint(equalToConstant: 260),
            decknameZeile.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -36),
            suche.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -36),
            decknameFeld.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
            originalFeld.widthAnchor.constraint(greaterThanOrEqualToConstant: 170),
        ])
    }

    private func baueKnoepfe() {
        knopfleiste.setViews([], in: .leading)
        for (index, kategorie) in Kategorie.schnellwahl.enumerated() {
            let knopf = NSButton(
                title: "\(kategorie.anzeigename) (⌘\(index + 1))",
                target: self,
                action: #selector(kategorieGeklickt(_:))
            )
            knopf.tag = index
            knopf.bezelStyle = .rounded
            knopf.controlSize = .small
            knopf.toolTip = "⌘\(index + 1) macht dasselbe"
            knopfleiste.addArrangedSubview(knopf)
        }

        let kopieren = NSButton(title: "Geschützten Text kopieren", target: self, action: #selector(kopierenGeklickt))
        kopieren.bezelStyle = .rounded
        kopieren.controlSize = .regular
        kopieren.keyEquivalent = "\r"
        kopieren.keyEquivalentModifierMask = [.command]
        kopieren.toolTip = "⌘⏎ macht dasselbe und merkt dabei alle offenen Vermutungen"
        knopfleiste.addArrangedSubview(kopieren)

        let verwerfen = NSButton(title: "Verwerfen", target: self, action: #selector(verwerfenGeklickt))
        verwerfen.toolTip = "Diese Stelle bleibt im Klartext stehen"
        let gruppe = NSButton(title: "Gehört zu … (⌘D)", target: self, action: #selector(gruppeGeklickt))
        gruppe.toolTip = "Als weitere Schreibweise an einen bekannten Eintrag hängen. ⌘D macht dasselbe."
        let neu = NSButton(title: "Neuer Text (⌘N)", target: self, action: #selector(neuEinlesen))
        neu.toolTip = "Liest, was jetzt in der Zwischenablage liegt. Der bisherige Text wird verworfen."
        vorschauKnopf = NSButton(title: "Vorschau (⌘E)", target: self, action: #selector(vorschauUmschalten))
        vorschauKnopf.toolTip = "Zeigt den Text mit eingesetzten Platzhaltern, so wie er rausgeht."
        let leeren = NSButton(title: "Leeren", target: self, action: #selector(leeren))
        leeren.toolTip = "Wirft den Text weg. Das Wörterbuch bleibt."
        for knopf in [verwerfen, gruppe, vorschauKnopf, leeren, neu] {
            knopf.bezelStyle = .rounded
            knopf.controlSize = .small
            knopfleiste.addArrangedSubview(knopf)
        }
    }

    // MARK: Darstellung

    private func aktualisiere(schreibmarke: NSRange? = nil) {
        reihenfolge = analyse.funde
            .filter { !$0.verworfen }
            .sorted { $0.bereich.location < $1.bereich.location }
            .map(\.id)
        auswahl = reihenfolge.isEmpty ? 0 : min(auswahl, reihenfolge.count - 1)

        let gewaehlt = reihenfolge.indices.contains(auswahl) ? reihenfolge[auswahl] : nil
        let aufbau = inVorschau
            ? Chiptext.aufbauen(analyse: analyse, ausgewaehlt: gewaehlt)
            : Chiptext.aufbauenOriginal(analyse: analyse, ausgewaehlt: gewaehlt)
        bereiche = aufbau.bereiche
        textAnsicht.textStorage?.setAttributedString(aufbau.text)
        if let schreibmarke, NSMaxRange(schreibmarke) <= textAnsicht.string.count {
            textAnsicht.setSelectedRange(schreibmarke)
        }

        beschrifteKopf()

        liste.zeige(
            analyse.funde.sorted { $0.bereich.location < $1.bereich.location }.map(listenzeile),
            ausgewaehlt: gewaehlt,
            leertext: analyse.original.isEmpty
                ? "Kein Text zum Prüfen."
                : "Nichts erkannt.\n\nMarkiere links im Text, was geschützt werden soll, und drücke 1–5."
        )

        if let gewaehlt, let bereich = bereiche[gewaehlt] {
            springeZu(bereich)
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
        let fund = aktuellerFund
        for ansicht in knopfleiste.arrangedSubviews {
            guard let knopf = ansicht as? NSButton else { continue }
            if knopf.title.hasPrefix("Gehört zu") {
                // Geht auch ohne Vorschlag: du weißt oft besser als die
                // Heuristik, wer gemeint ist.
                knopf.isEnabled = (fund != nil || hatFreieMarkierung)
                    && !analyse.woerterbuch.eintraege.isEmpty
                if let vorschlag = fund?.gruppenVorschlag,
                   let eintrag = analyse.woerterbuch.eintrag(mitId: vorschlag) {
                    knopf.toolTip = "Vorschlag: \(eintrag.text) (\(eintrag.platzhalter))"
                }
            } else {
                knopf.isEnabled = fund != nil || hatFreieMarkierung
            }
        }

        decknameFeld.isEnabled = fund != nil && !(fund?.verworfen ?? true)
        decknameFeld.stringValue = fund?.verworfen == false ? (fund?.platzhalter ?? "") : ""
        originalFeld.isEnabled = fund != nil
        originalFeld.stringValue = fund?.text ?? ""
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
        // In den beiden Textfeldern gehören die Tasten dem Feld.
        if decknameFeld.currentEditor() != nil || originalFeld.currentEditor() != nil {
            return false
        }


        let zusatz = ereignis.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if zusatz.contains(.command) {
            switch ereignis.charactersIgnoringModifiers?.lowercased() {
            case "n":
                neuEinlesen()
                return true
            case "e":
                vorschauUmschalten()
                return true
            case "f":
                suche.oeffne()
                return true
            case "g":
                if zusatz.contains(.shift) { suche.vorheriger() } else { suche.naechster() }
                return true
            case "1", "2", "3", "4", "5":
                if let ziffer = Int(ereignis.charactersIgnoringModifiers ?? ""),
                   Kategorie.schnellwahl.indices.contains(ziffer - 1) {
                    setzeKategorie(Kategorie.schnellwahl[ziffer - 1])
                    return true
                }
                return false
            case "d":
                gruppeUebernehmen()
                return true
            default:
                break
            }
            // ⌘C und Konsorten gehören der Textansicht, nur ⌘⏎ nicht.
            if ereignis.keyCode != 36, ereignis.keyCode != 76 { return false }
        }

        switch ereignis.keyCode {
        case 36, 76 where zusatz.contains(.command):  // ⌘⏎
            uebernehmen(merken: true)
            return true
        case 53:  // Escape
            abbrechen()
            return true
        case 126 where zusatz.contains(.option):  // ⌥ Pfeil hoch
            waehle(auswahl - 1)
            return true
        case 125 where zusatz.contains(.option):  // ⌥ Pfeil runter
            waehle(auswahl + 1)
            return true
        default:
            break
        }

        // Ziffern und Buchstaben ohne Befehlstaste gehören dem Text: er ist
        // bearbeitbar, da soll eine 1 eine 1 schreiben.
        return false
    }

    private func waehle(_ index: Int) {
        guard !reihenfolge.isEmpty else { return }
        auswahl = (index + reihenfolge.count) % reihenfolge.count
        textAnsicht.setSelectedRange(NSRange(location: 0, length: 0))
        zeigeMeldung(nil)
        aktualisiere()
    }

    /// Rollt zu einer Stelle und lässt sie kurz aufblitzen.
    ///
    /// Ohne `ensureLayout` weiß die Textansicht noch nicht, wo die Stelle
    /// liegt: der Text ist gerade erst gesetzt worden, gesetzt ist er aber
    /// noch nicht. Dann rollt sie nirgendwohin.
    private func springeZu(_ bereich: NSRange) {
        guard let layout = textAnsicht.layoutManager,
              let behaelter = textAnsicht.textContainer
        else { return }
        layout.ensureLayout(for: behaelter)
        textAnsicht.scrollRangeToVisible(bereich)
        textAnsicht.showFindIndicator(for: bereich)
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

    @objc private func kopierenGeklickt() { uebernehmen(merken: false) }

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

    /// Hängt die Nennung an einen bekannten Eintrag. Fragt, an welchen — der
    /// Heuristikvorschlag ist dabei nur vorausgewählt, nicht gesetzt.
    private func gruppeUebernehmen() {
        let nennung: String
        let bereich: NSRange?
        if let markierung = freieMarkierung {
            nennung = (analyse.original as NSString).substring(with: markierung)
            bereich = markierung
        } else if let fund = aktuellerFund {
            nennung = fund.text
            bereich = nil
        } else {
            return
        }

        guard let ziel = EintragWaehler.frage(
            woerterbuch: analyse.woerterbuch,
            fuer: nennung,
            vorschlag: aktuellerFund?.gruppenVorschlag
        ) else { return }

        let vorher = analyse.aktiveFunde.count
        if let bereich {
            guard let neue = Schleuse.markiereAlsSchreibweise(
                bereich: bereich,
                zu: ziel.id,
                in: &analyse
            ) else {
                zeigeMeldung("Das ließ sich nicht zuordnen.")
                return
            }
            textAnsicht.setSelectedRange(NSRange(location: 0, length: 0))
            aktualisiere()
            waehleFund(neue)
        } else if let fund = aktuellerFund {
            Schleuse.alsAliasZuordnen(fundId: fund.id, zu: ziel.id, in: &analyse)
            aktualisiere()
        }

        let dazu = analyse.aktiveFunde.count - vorher - (bereich == nil ? 0 : 1)
        var satz = "Als weitere Schreibweise von \(ziel.text) übernommen"
        if dazu > 0 { satz += ", \(dazu) weitere Stelle(n) mitgezogen" }
        meldung.textColor = .secondaryLabelColor
        meldung.stringValue = satz + "."
        meldung.isHidden = false
    }

    private func verwerfeAktuellen() {
        guard let fund = aktuellerFund else { return }
        Schleuse.verwerfe(fundId: fund.id, in: &analyse)
        aktualisiere()
    }

    // MARK: Für den Selbsttest

    func leerenFuerPruefung() { leeren() }
    func setzeTextFuerPruefung(_ text: String) {
        textAnsicht.string = text
        pruefeJetzt()
    }
    func istInVorschauFuerPruefung() -> Bool { inVorschau }
    func vorschauUmschaltenFuerPruefung() { vorschauUmschalten() }
    func waehleFundFuerPruefung(_ kennung: UUID) { waehleFund(kennung) }
    func setzeOriginalFuerPruefung(_ text: String) {
        originalFeld.stringValue = text
        originalUebernehmen()
    }

    /// Liegt die Fundstelle im sichtbaren Ausschnitt? Genau das ist gemeint,
    /// wenn der Text zur angeklickten Stelle springen soll.
    func fundIstSichtbarFuerPruefung(_ kennung: UUID) -> Bool {
        guard let bereich = bereiche[kennung],
              let layout = textAnsicht.layoutManager,
              let behaelter = textAnsicht.textContainer
        else { return false }
        layout.ensureLayout(for: behaelter)
        let zeichen = layout.glyphRange(forCharacterRange: bereich, actualCharacterRange: nil)
        var rahmen = layout.boundingRect(forGlyphRange: zeichen, in: behaelter)
        rahmen.origin.x += textAnsicht.textContainerOrigin.x
        rahmen.origin.y += textAnsicht.textContainerOrigin.y
        return textAnsicht.visibleRect.intersects(rahmen)
    }

    // MARK: Bearbeiten

    /// Schaltet zwischen dem bearbeitbaren Original und der Vorschau um.
    @objc private func vorschauUmschalten() {
        inVorschau.toggle()
        textAnsicht.isEditable = !inVorschau
        vorschauKnopf.title = inVorschau ? "Original (⌘E)" : "Vorschau (⌘E)"
        aktualisiere()
        if !inVorschau { window?.makeFirstResponder(textAnsicht) }
    }

    /// Wirft den Text weg und lässt dich gleich tippen. Ohne das müsste man
    /// erst irgendwas anderes kopieren, um den alten Text loszuwerden.
    @objc private func leeren() {
        inVorschau = false
        textAnsicht.isEditable = true
        analyse = Schleuse.analysiere("", woerterbuch: analyse.woerterbuch)
        auswahl = 0
        aktualisiere()
        window?.makeFirstResponder(textAnsicht)
    }

    /// Nimmt, was gerade im Textfeld steht, und prüft es neu.
    ///
    /// Läuft nach einer kurzen Pause, nicht bei jedem Anschlag: sonst würde
    /// mitten im Tippen eines Namens dessen halbe Fassung gemerkt.
    private func pruefeNachTippen() {
        nachdenkpause?.invalidate()
        nachdenkpause = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.pruefeJetzt()
        }
    }

    private func pruefeJetzt() {
        let getippt = textAnsicht.string
        guard getippt != analyse.original else { return }

        // Die Schreibmarke merken und danach zurücksetzen: das Neuzeichnen
        // ersetzt den ganzen Textspeicher und würde sie sonst an den Anfang
        // werfen.
        let marke = textAnsicht.selectedRange()
        analyse = Schleuse.analysiere(getippt, woerterbuch: analyse.woerterbuch)
        auswahl = 0
        aktualisiere(schreibmarke: marke)
    }

    /// Holt sich, was jetzt in der Zwischenablage liegt    /// Holt sich, was jetzt in der Zwischenablage liegt, und fängt damit von
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

    /// ⏎ im Original-Feld: den Text an dieser Stelle austauschen. Danach steht
    /// der Cursor im Deckname-Feld, also da, wo man als Nächstes hinwill.
    @objc private func originalUebernehmen() {
        guard let fund = aktuellerFund else { return }
        let eingabe = originalFeld.stringValue
        guard eingabe != fund.text else {
            window?.makeFirstResponder(decknameFeld)
            return
        }

        do {
            try Schleuse.ersetzeOriginaltext(fundId: fund.id, durch: eingabe, in: &analyse)
            zeigeMeldung(nil)
            aktualisiere()
            waehleFund(fund.id)
            window?.makeFirstResponder(decknameFeld)
            decknameFeld.currentEditor()?.selectAll(nil)
        } catch {
            zeigeMeldung(error.localizedDescription)
            originalFeld.currentEditor()?.selectAll(nil)
        }
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
        guard befehl == #selector(NSResponder.cancelOperation(_:)) else { return false }
        if steuerelement === decknameFeld {
            decknameAbbrechen()
            return true
        }
        if steuerelement === originalFeld {
            originalFeld.stringValue = aktuellerFund?.text ?? ""
            zeigeMeldung(nil)
            window?.makeFirstResponder(textAnsicht)
            return true
        }
        return false
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

    /// Jede Eingabe im Text löst nach einer kurzen Pause eine neue Prüfung aus.
    func textDidChange(_ meldung: Notification) {
        guard meldung.object as AnyObject? === textAnsicht, !inVorschau else { return }
        pruefeNachTippen()
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
