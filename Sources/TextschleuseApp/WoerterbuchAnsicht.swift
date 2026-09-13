import AppKit
import TextschleuseCore

/// Das Wörterbuch als Ansicht: oben die Liste mit Suchfeld, darunter der
/// Editor für den ausgewählten Eintrag.
///
/// Steht als eigene Ansicht da, weil sie an drei Stellen gebraucht wird: im
/// eigenen Fenster, dauerhaft im Hauptfenster und ausklappbar im Popup.
final class WoerterbuchAnsicht: NSView {

    private var woerterbuch: Woerterbuch
    private let beimSichern: (Woerterbuch) -> Void
    private let beimExportieren: (URL, Woerterbuch) throws -> Void

    /// Links: was im gerade bearbeiteten Text vorkommt. Rechts: alles, was
    /// im Wörterbuch steht.
    ///
    /// Die Trennung beantwortet zwei verschiedene Fragen. Beim Arbeiten am
    /// Text will man wissen, was hier greift; beim Pflegen, was es überhaupt
    /// gibt. In einer Liste vermischt sich das.
    private let tabelleImText = NSTableView()
    private let tabelle = NSTableView()
    private var imText: Set<UUID> = []
    private var zeilenImText: [Zeile] = []
    private let ueberschriftImText = NSTextField(labelWithString: "Im Text")
    private let ueberschriftAlle = NSTextField(labelWithString: "Alle Einträge")
    private let leerImText = NSTextField(wrappingLabelWithString:
        "Noch kein Text geprüft.\n\nWas hier greift, steht dann hier.")
    fileprivate let editor = EintragEditor()
    private let zaehler = NSTextField(labelWithString: "")
    private let suchfeld = NSSearchField()
    private let aufloesungZeile = NSTextField(wrappingLabelWithString: "")

    /// Flachgeklopfte Darstellung: Hauptnennung, danach ihre Aliase.
    private struct Zeile {
        var eintragId: UUID
        var istAlias: Bool
        var text: String
        var platzhalter: String
        var kategorie: String
        var herkunft: String
        /// Trennzeile über einem Typblock. Trägt keine Daten und lässt sich
        /// nicht auswählen; `eintragId` ist dann bedeutungslos.
        var istKopf: Bool = false
    }

    private var zeilen: [Zeile] = []
    /// Bleibt über einen Neuaufbau der Liste hinweg erhalten, damit der Editor
    /// nach jeder Änderung denselben Eintrag zeigt.
    fileprivate var ausgewaehlt: UUID?


    /// `schmal` heißt: Liste und Editor untereinander statt nebeneinander.
    /// Für die Spalte im Hauptfenster und die Klappe im Popup.
    private let schmal: Bool

    init(
        woerterbuch: Woerterbuch,
        schmal: Bool = false,
        beimSichern: @escaping (Woerterbuch) -> Void,
        beimExportieren: @escaping (URL, Woerterbuch) throws -> Void
    ) {
        self.woerterbuch = woerterbuch
        self.schmal = schmal
        self.beimSichern = beimSichern
        self.beimExportieren = beimExportieren
        super.init(frame: NSRect(x: 0, y: 0, width: schmal ? 340 : 980, height: 560))

        baueOberflaeche()
        aktualisiere()
    }

    /// Nimmt einen neuen Stand von außen an — etwa wenn im Popup gerade ein
    /// Eintrag entstanden ist.
    func setze(woerterbuch neues: Woerterbuch) {
        woerterbuch = neues
        aktualisiere()
    }

    /// Sagt, welche Einträge im gerade bearbeiteten Text vorkommen. Sie stehen
    /// dann links, alles andere rechts.
    func setze(imText kennungen: Set<UUID>) {
        guard kennungen != imText else { return }
        imText = kennungen
        aktualisiere()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }

    private func baueOberflaeche() {
        // Im schmalen Fall bleibt kein Platz für Spalten nebeneinander. Eine
        // einzige Spalte ohne Kopfzeile, Begriff und Deckname übereinander —
        // Typ und Herkunft stehen im Editor.
        let spaltenBeschreibung: [(String, String, Double)] = schmal
            ? [("text", "Begriff", 180.0)]
            : [
                ("text", "Begriff", 220.0),
                ("platzhalter", "Deckname", 130.0),
                ("kategorie", "Typ", 100.0),
                ("herkunft", "Herkunft", 120.0),
            ]
        for (kennung, titel, breite) in spaltenBeschreibung {
            let spalte = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(kennung))
            spalte.title = titel
            spalte.width = breite
            spalte.resizingMask = .autoresizingMask
            tabelle.addTableColumn(spalte)
        }
        tabelle.dataSource = self
        tabelle.delegate = self
        tabelle.usesAlternatingRowBackgroundColors = true
        tabelle.allowsMultipleSelection = true
        if schmal {
            tabelle.headerView = nil
            tabelle.rowHeight = 26
            tabelle.style = .inset
        }

        // Die linke Tabelle zeigt dieselben Spalten, nur gefiltert.
        for spalte in tabelle.tableColumns {
            let kopie = NSTableColumn(identifier: spalte.identifier)
            kopie.title = spalte.title
            kopie.width = spalte.width
            kopie.resizingMask = .autoresizingMask
            tabelleImText.addTableColumn(kopie)
        }
        tabelleImText.dataSource = self
        tabelleImText.delegate = self
        tabelleImText.usesAlternatingRowBackgroundColors = true
        if schmal {
            tabelleImText.headerView = nil
            tabelleImText.rowHeight = 26
            tabelleImText.style = .inset
        }

        let rollflaeche = NSScrollView()
        rollflaeche.documentView = tabelle
        rollflaeche.hasVerticalScroller = true
        rollflaeche.borderType = .bezelBorder
        rollflaeche.translatesAutoresizingMaskIntoConstraints = false

        let rolleImText = NSScrollView()
        rolleImText.documentView = tabelleImText
        rolleImText.hasVerticalScroller = true
        rolleImText.borderType = .bezelBorder
        rolleImText.translatesAutoresizingMaskIntoConstraints = false

        // Der überlagernde Rollbalken blendet sich aus, sobald man die Maus
        // wegnimmt. Bei 97 Einträgen und zwölf sichtbaren Zeilen sieht man
        // dann nicht, dass da noch etwas kommt.
        for rolle in [rollflaeche, rolleImText] where schmal {
            rolle.scrollerStyle = .legacy
            rolle.autohidesScrollers = false
        }

        for kopf in [ueberschriftImText, ueberschriftAlle] {
            kopf.font = .systemFont(ofSize: 11, weight: .semibold)
            kopf.textColor = .secondaryLabelColor
        }
        leerImText.font = .systemFont(ofSize: 11)
        leerImText.textColor = .tertiaryLabelColor
        leerImText.alignment = .center
        leerImText.translatesAutoresizingMaskIntoConstraints = false
        rolleImText.addSubview(leerImText)
        NSLayoutConstraint.activate([
            leerImText.centerXAnchor.constraint(equalTo: rolleImText.centerXAnchor),
            leerImText.centerYAnchor.constraint(equalTo: rolleImText.centerYAnchor),
            leerImText.widthAnchor.constraint(equalTo: rolleImText.widthAnchor, constant: -32),
        ])

        editor.translatesAutoresizingMaskIntoConstraints = false
        editor.beiBefehl = { [weak self] befehl in self?.fuehreAus(befehl) }

        suchfeld.placeholderString = "Begriff oder Deckname, etwa PERSON_3"
        suchfeld.target = self
        suchfeld.action = #selector(gefiltert)
        suchfeld.sendsWholeSearchString = false
        suchfeld.sendsSearchStringImmediately = true
        suchfeld.translatesAutoresizingMaskIntoConstraints = false

        zaehler.font = .systemFont(ofSize: 11)
        zaehler.textColor = .secondaryLabelColor
        // Der Zähler ist Beiwerk. Er darf die Spalte nicht auseinanderziehen,
        // lieber verliert er sein Ende.
        zaehler.lineBreakMode = .byTruncatingTail
        zaehler.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Die ausgeschriebenen Titel drücken die Leiste auf 540 Punkte und
        // damit die ganze Spalte im Hauptfenster. Schmal heißt kurz; was der
        // Knopf tut, sagt der Tooltip.
        let loeschen = NSButton(title: "Löschen", target: self, action: #selector(loescheAuswahl))
        let autoLeeren = NSButton(
            title: schmal ? "Auto leeren" : "Automatisch erkannte leeren",
            target: self,
            action: #selector(leereAutomatische)
        )
        autoLeeren.toolTip = "Automatisch erkannte Einträge löschen"
        let exportieren = NSButton(
            title: schmal ? "Export …" : "Klartext-Export …",
            target: self,
            action: #selector(exportiere)
        )
        exportieren.toolTip = "Klartext-Export, unverschlüsselt"
        for knopf in [loeschen, autoLeeren, exportieren] {
            knopf.bezelStyle = .rounded
        }

        let knopfleiste = NSStackView(views: [loeschen, autoLeeren, exportieren, NSView(), zaehler])
        knopfleiste.orientation = .horizontal
        knopfleiste.spacing = 8
        knopfleiste.translatesAutoresizingMaskIntoConstraints = false

        // In einer Zeile ist der Satz 490 Punkte breit und legt damit die
        // Mindestbreite der ganzen Spalte fest. Schmal darf er umbrechen.
        let hinweistext = "Gelöschte Nummern werden nicht neu vergeben. "
            + "Der Klartext-Export ist unverschlüsselt."
        let hinweis = schmal
            ? NSTextField(wrappingLabelWithString: hinweistext)
            : NSTextField(labelWithString: hinweistext)
        hinweis.font = .systemFont(ofSize: 11)
        hinweis.textColor = .secondaryLabelColor
        // Ohne diese Vorgabe rechnet ein umbrechendes Feld seine Wunschbreite
        // als eine einzige Zeile aus — und die wären hier 469 Punkte.
        if schmal { hinweis.preferredMaxLayoutWidth = 320 }

        aufloesungZeile.font = .systemFont(ofSize: 12)
        aufloesungZeile.isHidden = true

        let spalteImText = NSStackView(views: [ueberschriftImText, rolleImText])
        spalteImText.orientation = .vertical
        spalteImText.spacing = 4
        spalteImText.translatesAutoresizingMaskIntoConstraints = false

        let spalteAlle = NSStackView(views: [ueberschriftAlle, rollflaeche])
        spalteAlle.orientation = .vertical
        spalteAlle.spacing = 4
        spalteAlle.translatesAutoresizingMaskIntoConstraints = false

        let nebeneinander = NSStackView(views: [spalteImText, spalteAlle])
        nebeneinander.orientation = .horizontal
        nebeneinander.spacing = 12
        nebeneinander.distribution = .fillEqually
        nebeneinander.translatesAutoresizingMaskIntoConstraints = false

        // Das Suchfeld steht über beiden Listen, nicht nur über der rechten.
        // Vorher begann die linke Liste eine Suchfeldhöhe weiter oben als die
        // rechte, und das sah schief aus.
        let links = NSStackView(views: [suchfeld, aufloesungZeile, nebeneinander])
        links.orientation = .vertical
        links.spacing = 6
        links.translatesAutoresizingMaskIntoConstraints = false

        // Rollflächen haben keine eigene Größe. In einem einzelnen Stapel
        // bekommen sie den Rest, aber sobald Stapel ineinander stecken,
        // reicht niemand die Höhe durch — dann fallen sie auf null zusammen
        // und die Liste ist unsichtbar, obwohl alle Zeilen da sind.
        for rolle in [rollflaeche, rolleImText] {
            rolle.setContentHuggingPriority(.defaultLow, for: .vertical)
            rolle.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        }
        // Der Editor darunter nimmt sich, was er braucht, und nicht mehr —
        // den Rest bekommen die Listen.
        editor.setContentHuggingPriority(.required, for: .vertical)
        links.setContentHuggingPriority(.defaultLow, for: .vertical)
        if schmal {
            // Der Editor hat keine eigene Höhe, nur seine Teile. Damit
            // greift das Hugging nicht, und wer den Rest bekommt, entschied
            // bisher der Zufall der Constraint-Reihenfolge — mal die Listen,
            // mal der Editor. Der Wunsch „so niedrig wie möglich" mit
            // kleinster Priorität macht es eindeutig: der Editor bleibt bei
            // seinem Inhalt, die Listen wachsen.
            let niedrig = editor.heightAnchor.constraint(equalToConstant: 0)
            niedrig.priority = NSLayoutConstraint.Priority(1)
            niedrig.isActive = true
        }
        for kopf in [ueberschriftImText, ueberschriftAlle] {
            kopf.setContentHuggingPriority(.required, for: .vertical)
        }
        suchfeld.setContentHuggingPriority(.required, for: .vertical)
        aufloesungZeile.setContentHuggingPriority(.required, for: .vertical)

        let mitte = NSStackView(views: [links, editor])
        mitte.orientation = schmal ? .vertical : .horizontal
        mitte.spacing = schmal ? 10 : 16
        mitte.distribution = .fill
        mitte.translatesAutoresizingMaskIntoConstraints = false

        let stapel = NSStackView(views: [mitte, knopfleiste, hinweis])
        stapel.orientation = .vertical
        stapel.spacing = 10
        stapel.alignment = .leading
        stapel.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stapel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stapel)
        NSLayoutConstraint.activate([
            stapel.topAnchor.constraint(equalTo: topAnchor),
            stapel.leadingAnchor.constraint(equalTo: leadingAnchor),
            stapel.trailingAnchor.constraint(equalTo: trailingAnchor),
            stapel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        knopfleiste.setContentHuggingPriority(.required, for: .vertical)
        hinweis.setContentHuggingPriority(.required, for: .vertical)
        mitte.setContentHuggingPriority(.defaultLow, for: .vertical)
        mitte.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        NSLayoutConstraint.activate([
            mitte.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -32),
            mitte.heightAnchor.constraint(greaterThanOrEqualToConstant: schmal ? 210 : 380),
            knopfleiste.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -32),
            hinweis.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -32),
            suchfeld.widthAnchor.constraint(equalTo: links.widthAnchor),
            aufloesungZeile.widthAnchor.constraint(equalTo: links.widthAnchor),
            nebeneinander.widthAnchor.constraint(equalTo: links.widthAnchor),
            rollflaeche.widthAnchor.constraint(equalTo: spalteAlle.widthAnchor),
            rolleImText.widthAnchor.constraint(equalTo: spalteImText.widthAnchor),

            // Ohne diese Maße bleibt von den Listen nichts übrig. Schmal
            // stehen Listen und Editor untereinander — dort müssen die Maße
            // kleiner sein, sonst fordert die Spalte 809 Punkte Höhe und das
            // Hauptfenster passt auf kein 13-Zoll-Bild mehr.
            links.widthAnchor.constraint(equalTo: mitte.widthAnchor),
            nebeneinander.heightAnchor.constraint(greaterThanOrEqualToConstant: schmal ? 210 : 380),
            rollflaeche.heightAnchor.constraint(greaterThanOrEqualToConstant: schmal ? 130 : 200),
            rolleImText.heightAnchor.constraint(greaterThanOrEqualToConstant: schmal ? 130 : 200),
            rollflaeche.bottomAnchor.constraint(equalTo: spalteAlle.bottomAnchor),
            rolleImText.bottomAnchor.constraint(equalTo: spalteImText.bottomAnchor),
            schmal
                ? editor.widthAnchor.constraint(equalTo: mitte.widthAnchor)
                : editor.widthAnchor.constraint(equalToConstant: 340),
        ])
    }

    // MARK: Darstellung

    private func aktualisiere() {
        let filter = suchfeld.stringValue.trimmingCharacters(in: .whitespaces).lowercased()

        // Frühere Decknamen findet die gemeinsame Suche nicht — sie kennt nur
        // die aktuellen. Wer eine alte Mail zurückdreht, sucht aber genau
        // danach, deshalb hier zusätzlich.
        let treffer = Eintragsliste.gefiltert(woerterbuch.eintraege, suche: filter)
        let nachAltnamen = filter.isEmpty ? [] : woerterbuch.eintraege.filter { eintrag in
            eintrag.alleDecknamen.contains { $0.lowercased().contains(filter) }
        }
        let alleTreffer = treffer + nachAltnamen.filter { alt in !treffer.contains { $0.id == alt.id } }

        // Nach Typ geclustert, innerhalb alphabetisch — dieselbe Ordnung wie
        // beim Zuordnen. Bei 97 Einträgen findet man in einer flachen Liste
        // nach Nummer sonst gar nichts.
        zeilen = Eintragsliste.gruppiert(alleTreffer).flatMap { gruppe -> [Zeile] in
            let kopf = Zeile(
                eintragId: UUID(),
                istAlias: false,
                text: "\(gruppe.kategorie.anzeigename)  ·  \(gruppe.eintraege.count)",
                platzhalter: "",
                kategorie: gruppe.kategorie.anzeigename,
                herkunft: "",
                istKopf: true
            )
            return [kopf] + gruppe.eintraege.flatMap { eintrag -> [Zeile] in
                let haupt = Zeile(
                    eintragId: eintrag.id,
                    istAlias: false,
                    text: eintrag.text,
                    platzhalter: eintrag.platzhalter,
                    kategorie: eintrag.kategorie.anzeigename,
                    herkunft: eintrag.automatischErkannt ? "automatisch erkannt" : "gemerkt"
                )
                let aliase = eintrag.aliase.map { alias in
                    Zeile(
                        eintragId: eintrag.id,
                        istAlias: true,
                        text: "↳ \(alias.text)",
                        platzhalter: eintrag.platzhalter(fuer: alias),
                        kategorie: eintrag.kategorie.anzeigename,
                        herkunft: "Schreibweise"
                    )
                }
                return [haupt] + aliase
            }
        }

        // Die linke Liste ist kurz — dort wären Typköpfe nur Ballast.
        zeilenImText = zeilen.filter { !$0.istKopf && imText.contains($0.eintragId) }
        ueberschriftImText.stringValue = zeilenImText.isEmpty
            ? "Im Text"
            : "Im Text (\(Set(zeilenImText.map(\.eintragId)).count))"
        ueberschriftAlle.stringValue = "Alle Einträge (\(woerterbuch.eintraege.count))"
        leerImText.isHidden = !zeilenImText.isEmpty
        tabelleImText.reloadData()

        let anzahl = woerterbuch.eintraege.count
        let automatisch = woerterbuch.eintraege.filter(\.automatischErkannt).count
        zaehler.stringValue = filter.isEmpty
            ? (schmal
                ? "\(anzahl) Einträge, \(automatisch) automatisch"
                : "\(anzahl) Einträge, davon \(automatisch) automatisch erkannt")
            : "\(Set(zeilen.map(\.eintragId)).count) von \(anzahl) Einträgen"

        beschrifteAufloesung()
        tabelle.reloadData()
        stelleAuswahlWiederHer()
        editor.zeige(ausgewaehlt.flatMap { woerterbuch.eintrag(mitId: $0) })
    }

    /// Die Antwort auf „wer war nochmal PERSON_3?" in einem Satz, direkt über
    /// der Liste. Erscheint nur, wenn die Eingabe wirklich ein Deckname ist.
    private func beschrifteAufloesung() {
        guard let treffer = woerterbuch.aufloesen(suchfeld.stringValue) else {
            // Auch den Text leeren, nicht nur ausblenden: eine versteckte
            // Beschriftung mit altem Inhalt ist eine Falle.
            aufloesungZeile.stringValue = ""
            aufloesungZeile.isHidden = true
            return
        }

        var satz = "\(suchfeld.stringValue.uppercased()) ist \(treffer.klartext)"
        if treffer.alias != nil {
            satz += " — eine Schreibweise von \(treffer.eintrag.text)"
        }
        if treffer.istFrueherer {
            satz += ". Früherer Deckname, heute heißt der Eintrag \(treffer.eintrag.platzhalter)"
        }
        aufloesungZeile.stringValue = satz + "."
        aufloesungZeile.textColor = treffer.istFrueherer ? .secondaryLabelColor : .labelColor
        aufloesungZeile.isHidden = false
    }

    private func stelleAuswahlWiederHer() {
        guard let ausgewaehlt,
              let index = zeilen.firstIndex(where: { $0.eintragId == ausgewaehlt && !$0.istAlias })
        else { return }
        tabelle.selectRowIndexes([index], byExtendingSelection: false)
    }

    private func sichere() {
        beimSichern(woerterbuch)
        aktualisiere()
    }

    // MARK: Befehle aus dem Editor

    /// Führt aus, was der Editor meldet. Rückgabe `nil` heißt: hat geklappt.
    private func fuehreAus(_ befehl: EintragEditor.Befehl) -> String? {
        guard let kennung = ausgewaehlt else { return nil }
        do {
            switch befehl {
            case .begriff(let text):
                try woerterbuch.aendereText(kennung, auf: text)
            case .kategorie(let kategorie):
                woerterbuch.aendereKategorie(kennung, auf: kategorie)
            case .deckname(let name):
                _ = try woerterbuch.umbenennen(kennung, auf: name)
            case .decknameZuruecksetzen:
                woerterbuch.decknameZuruecksetzen(kennung)
            case .aliasNeu(let text):
                guard woerterbuch.aliasHinzufuegen(text, zu: kennung) != nil else {
                    return "Diese Schreibweise gibt es schon."
                }
            case .aliasText(let aliasId, let text):
                try woerterbuch.aendereAlias(aliasId, in: kennung, auf: text)
            case .aliasLoeschen(let aliasId):
                woerterbuch.loescheAlias(aliasId, in: kennung)
            case .aliasHauptnennung(let aliasId):
                woerterbuch.machtZurHauptnennung(aliasId, in: kennung)
            }
        } catch {
            // Nichts wurde geändert; die Meldung geht zurück in den Editor.
            aktualisiere()
            return error.localizedDescription
        }
        sichere()
        return nil
    }

    // MARK: Aktionen

    @objc private func gefiltert() { aktualisiere() }

    /// Wie `gefiltert`, aber von außen aufrufbar. Das Suchfeld meldet sich bei
    /// programmgesteuerter Eingabe nicht von selbst.
    func filterGeaendert() { aktualisiere() }

    @objc private func loescheAuswahl() {
        let betroffen = Set(tabelle.selectedRowIndexes.compactMap { zeilen[$0].eintragId })
        guard !betroffen.isEmpty else { return }

        let meldung = NSAlert()
        meldung.messageText = betroffen.count == 1
            ? "Diesen Eintrag löschen?"
            : "\(betroffen.count) Einträge löschen?"
        meldung.informativeText =
            "Die Nummern bleiben verbrannt. Texte, die du schon verschickt hast, lassen sich damit nicht mehr zurückdrehen."
        meldung.addButton(withTitle: "Löschen")
        meldung.addButton(withTitle: "Abbrechen")
        guard meldung.runModal() == .alertFirstButtonReturn else { return }

        for kennung in betroffen { woerterbuch.loeschen(kennung) }
        if let ausgewaehlt, betroffen.contains(ausgewaehlt) { self.ausgewaehlt = nil }
        sichere()
    }

    @objc private func leereAutomatische() {
        let meldung = NSAlert()
        meldung.messageText = "Automatisch erkannte Einträge löschen?"
        meldung.informativeText =
            "Betrifft E-Mail-Adressen, Telefonnummern, IBANs und Ähnliches. Antworten auf ältere Texte lassen sich danach nicht mehr zurückdrehen."
        meldung.addButton(withTitle: "Löschen")
        meldung.addButton(withTitle: "Abbrechen")
        guard meldung.runModal() == .alertFirstButtonReturn else { return }

        woerterbuch.automatischErkannteLoeschen()
        ausgewaehlt = nil
        sichere()
    }

    @objc private func exportiere() {
        let meldung = NSAlert()
        meldung.messageText = "Export im Klartext"
        meldung.informativeText =
            "Die Datei ist unverschlüsselt und enthält echte Namen, Adressen und Bankdaten. Jeder, der sie öffnet, liest alles."
        meldung.addButton(withTitle: "Fortfahren")
        meldung.addButton(withTitle: "Abbrechen")
        guard meldung.runModal() == .alertFirstButtonReturn else { return }

        let auswahl = NSSavePanel()
        auswahl.nameFieldStringValue = "textschleuse-woerterbuch.json"
        auswahl.allowedContentTypes = [.json]
        guard auswahl.runModal() == .OK, let ziel = auswahl.url else { return }

        do {
            try beimExportieren(ziel, woerterbuch)
        } catch {
            let fehler = NSAlert()
            fehler.messageText = "Der Export ist fehlgeschlagen"
            fehler.informativeText = error.localizedDescription
            fehler.runModal()
        }
    }
}

extension WoerterbuchAnsicht: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === tabelleImText ? zeilenImText.count : zeilen.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let quelle = tableView === tabelleImText ? zeilenImText : zeilen
        guard let spalte = tableColumn?.identifier.rawValue, quelle.indices.contains(row) else {
            return nil
        }
        let zeile = quelle[row]
        if zeile.istKopf {
            guard spalte == "text" else { return nil }
            let titel = NSTextField(labelWithString: zeile.text)
            titel.font = .systemFont(ofSize: 11, weight: .semibold)
            titel.textColor = .secondaryLabelColor
            return titel
        }
        if schmal { return schmaleZelle(zeile) }

        let inhalt: String
        switch spalte {
        case "text": inhalt = zeile.text
        case "platzhalter": inhalt = zeile.platzhalter
        case "kategorie": inhalt = zeile.kategorie
        default: inhalt = zeile.herkunft
        }

        let feld = NSTextField(labelWithString: inhalt)
        feld.font = spalte == "platzhalter"
            ? .monospacedSystemFont(ofSize: 11, weight: .regular)
            : .systemFont(ofSize: 12)
        feld.textColor = zeile.istAlias ? .secondaryLabelColor : .labelColor
        feld.lineBreakMode = .byTruncatingTail
        return feld
    }

    /// Begriff und Deckname übereinander in einer Zelle. Nebeneinander
    /// bräuchten sie 250 Punkte; in der schmalen Spalte stehen nur 190 zur
    /// Verfügung, und dann wird aus „Deckname" ein „D".
    private func schmaleZelle(_ zeile: Zeile) -> NSView {
        let begriff = NSTextField(labelWithString: zeile.text)
        begriff.font = .systemFont(ofSize: 11, weight: zeile.istAlias ? .regular : .medium)
        begriff.textColor = zeile.istAlias ? .secondaryLabelColor : .labelColor
        begriff.lineBreakMode = .byTruncatingTail

        let deckname = NSTextField(labelWithString: zeile.platzhalter)
        deckname.font = .monospacedSystemFont(ofSize: 9, weight: .regular)
        deckname.textColor = .secondaryLabelColor
        deckname.lineBreakMode = .byTruncatingTail

        let texte = NSStackView(views: [begriff, deckname])
        texte.orientation = .vertical
        texte.spacing = 0
        texte.alignment = .leading
        texte.translatesAutoresizingMaskIntoConstraints = false

        let zelle = NSTableCellView()
        zelle.addSubview(texte)
        NSLayoutConstraint.activate([
            // Schreibweisen rücken ein, damit sie als Anhängsel lesbar sind.
            texte.leadingAnchor.constraint(
                equalTo: zelle.leadingAnchor,
                constant: zeile.istAlias ? 16 : 4
            ),
            texte.trailingAnchor.constraint(equalTo: zelle.trailingAnchor, constant: -4),
            texte.centerYAnchor.constraint(equalTo: zelle.centerYAnchor),
        ])
        return zelle
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        let quelle = tableView === tabelleImText ? zeilenImText : zeilen
        return quelle.indices.contains(row) && quelle[row].istKopf
    }

    /// Typköpfe lassen sich nicht anwählen — die Pfeiltasten überspringen sie
    /// dadurch von selbst, und der Editor bekommt nie eine leere Zeile.
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        let quelle = tableView === tabelleImText ? zeilenImText : zeilen
        return quelle.indices.contains(row) && !quelle[row].istKopf
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        let quelle = tableView === tabelleImText ? zeilenImText : zeilen
        if quelle.indices.contains(row), quelle[row].istKopf { return 22 }
        return tableView.rowHeight
    }

    func tableViewSelectionDidChange(_ meldung: Notification) {
        guard let welche = meldung.object as? NSTableView else { return }
        let quelle = welche === tabelleImText ? zeilenImText : zeilen
        guard quelle.indices.contains(welche.selectedRow) else { return }
        // Die andere Liste die Auswahl fallen lassen, sonst stünden zwei
        // Zeilen markiert da und man wüsste nicht, welche der Editor zeigt.
        let andere = welche === tabelleImText ? tabelle : tabelleImText
        if andere.selectedRow != -1 { andere.deselectAll(nil) }
        waehle(quelle[welche.selectedRow].eintragId)
    }
}

extension WoerterbuchAnsicht {

    /// Wählt einen Eintrag aus und zeigt ihn im Editor.
    ///
    /// Steht hier und nicht nur im Delegaten, weil `selectRowIndexes` die
    /// Benachrichtigung nicht in jedem Fall auslöst. Wer die Auswahl
    /// programmgesteuert setzt — der Selbsttest etwa —, ruft das hier.
    func waehle(_ kennung: UUID?) {
        ausgewaehlt = kennung
        editor.zeige(kennung.flatMap { woerterbuch.eintrag(mitId: $0) })
    }
}
