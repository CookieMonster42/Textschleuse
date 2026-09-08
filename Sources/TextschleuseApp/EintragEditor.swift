import AppKit
import TextschleuseCore

/// Die rechte Hälfte des Wörterbuchfensters: alles an einem Eintrag, was sich
/// ändern lässt.
///
/// Der Editor ändert nichts selbst. Er schickt Befehle nach oben und bekommt
/// entweder `nil` zurück oder eine Fehlermeldung, die er anzeigt. Die Prüfung,
/// ob ein Deckname frei ist oder ein Begriff doppelt, gehört in den Kern, nicht
/// in ein Formular.
final class EintragEditor: NSView {

    enum Befehl {
        case begriff(String)
        case kategorie(Kategorie)
        case deckname(String)
        case decknameZuruecksetzen
        case aliasNeu(String)
        case aliasText(UUID, String)
        case aliasLoeschen(UUID)
        case aliasHauptnennung(UUID)
    }

    /// Liefert `nil`, wenn es geklappt hat, sonst den Text der Fehlermeldung.
    var beiBefehl: ((Befehl) -> String?)?

    private var eintrag: Eintrag?

    private let ueberschrift = NSTextField(labelWithString: "Eintrag")
    private let begriffFeld = NSTextField()
    private let kategorieWahl = NSPopUpButton()
    private let decknameFeld = NSTextField()
    private let zuruecksetzenKnopf = NSButton()
    private let fruehereZeile = NSTextField(wrappingLabelWithString: "")
    private let aliasTabelle = NSTableView()
    private let aliasRolle = NSScrollView()
    private let aliasKnoepfe = NSStackView()
    private let meldung = NSTextField(wrappingLabelWithString: "")
    private let leerhinweis = NSTextField(wrappingLabelWithString:
        "Wähle links einen Eintrag aus, um ihn zu bearbeiten.")
    private var felder: [NSView] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        baueAuf()
        zeige(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }

    private func baueAuf() {
        ueberschrift.font = .systemFont(ofSize: 13, weight: .semibold)
        ueberschrift.lineBreakMode = .byTruncatingTail

        begriffFeld.target = self
        begriffFeld.action = #selector(begriffGeaendert)
        begriffFeld.toolTip = "So steht der Begriff im Text. ⏎ übernimmt."

        for kategorie in Kategorie.allCases where kategorie != .unbekannt {
            kategorieWahl.addItem(withTitle: kategorie.anzeigename)
            kategorieWahl.lastItem?.representedObject = kategorie.rawValue
        }
        kategorieWahl.target = self
        kategorieWahl.action = #selector(kategorieGeaendert)

        decknameFeld.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        decknameFeld.target = self
        decknameFeld.action = #selector(decknameGeaendert)
        decknameFeld.toolTip = "Großbuchstaben, Ziffern, Unterstrich. ⏎ übernimmt."

        zuruecksetzenKnopf.title = "Zurücksetzen"
        zuruecksetzenKnopf.bezelStyle = .rounded
        zuruecksetzenKnopf.controlSize = .small
        zuruecksetzenKnopf.target = self
        zuruecksetzenKnopf.action = #selector(decknameZurueckgesetzt)
        zuruecksetzenKnopf.toolTip = "Zurück auf die automatische Nummer"

        fruehereZeile.font = .systemFont(ofSize: 11)
        fruehereZeile.textColor = .secondaryLabelColor

        let aliasSpalte = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("alias"))
        aliasSpalte.resizingMask = .autoresizingMask
        aliasTabelle.addTableColumn(aliasSpalte)
        aliasTabelle.headerView = nil
        aliasTabelle.rowHeight = 22
        aliasTabelle.style = .inset
        aliasTabelle.dataSource = self
        aliasTabelle.delegate = self
        aliasRolle.documentView = aliasTabelle
        aliasRolle.hasVerticalScroller = true
        aliasRolle.borderType = .bezelBorder
        aliasRolle.translatesAutoresizingMaskIntoConstraints = false

        aliasKnoepfe.orientation = .horizontal
        aliasKnoepfe.spacing = 6
        for (titel, aktion, hinweis) in [
            ("Hinzufügen …", #selector(aliasHinzufuegen), "Eine weitere Schreibweise desselben Begriffs"),
            ("Ändern …", #selector(aliasAendern), "Schreibweise korrigieren, der Buchstabe bleibt"),
            ("Löschen", #selector(aliasLoeschen), "Schreibweise entfernen"),
            ("Zur Hauptnennung", #selector(aliasHauptnennung), "Tauscht sie mit der Hauptnennung"),
        ] as [(String, Selector, String)] {
            let knopf = NSButton(title: titel, target: self, action: aktion)
            knopf.bezelStyle = .rounded
            knopf.controlSize = .small
            knopf.toolTip = hinweis
            aliasKnoepfe.addArrangedSubview(knopf)
        }

        meldung.font = .systemFont(ofSize: 11)
        meldung.textColor = .systemRed
        meldung.isHidden = true

        leerhinweis.font = .systemFont(ofSize: 12)
        leerhinweis.textColor = .tertiaryLabelColor
        leerhinweis.alignment = .center

        let stapel = NSStackView(views: [
            ueberschrift,
            beschriftet("Begriff", begriffFeld),
            beschriftet("Typ", kategorieWahl),
            beschriftet("Deckname", NSStackView(views: [decknameFeld, zuruecksetzenKnopf])),
            fruehereZeile,
            beschriftung("Weitere Schreibweisen"),
            aliasRolle,
            aliasKnoepfe,
            meldung,
        ])
        stapel.orientation = .vertical
        stapel.spacing = 8
        stapel.alignment = .leading
        stapel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stapel)
        addSubview(leerhinweis)
        leerhinweis.translatesAutoresizingMaskIntoConstraints = false

        felder = [begriffFeld, kategorieWahl, decknameFeld, zuruecksetzenKnopf, aliasTabelle]

        NSLayoutConstraint.activate([
            stapel.topAnchor.constraint(equalTo: topAnchor),
            stapel.leadingAnchor.constraint(equalTo: leadingAnchor),
            stapel.trailingAnchor.constraint(equalTo: trailingAnchor),
            stapel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            aliasRolle.widthAnchor.constraint(equalTo: stapel.widthAnchor),
            aliasRolle.heightAnchor.constraint(greaterThanOrEqualToConstant: 110),
            begriffFeld.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            decknameFeld.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
            leerhinweis.centerYAnchor.constraint(equalTo: centerYAnchor),
            leerhinweis.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            leerhinweis.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
        ])
    }

    private func beschriftung(_ text: String) -> NSTextField {
        let feld = NSTextField(labelWithString: text)
        feld.font = .systemFont(ofSize: 11, weight: .semibold)
        feld.textColor = .secondaryLabelColor
        return feld
    }

    private func beschriftet(_ titel: String, _ inhalt: NSView) -> NSView {
        let stapel = NSStackView(views: [beschriftung(titel), inhalt])
        stapel.orientation = .vertical
        stapel.spacing = 2
        stapel.alignment = .leading
        return stapel
    }

    // MARK: Anzeigen

    func zeige(_ neuer: Eintrag?) {
        eintrag = neuer
        meldung.isHidden = true
        leerhinweis.isHidden = neuer != nil
        for feld in felder { (feld as? NSControl)?.isEnabled = neuer != nil }

        guard let neuer else {
            ueberschrift.stringValue = ""
            begriffFeld.stringValue = ""
            decknameFeld.stringValue = ""
            fruehereZeile.stringValue = ""
            aliasTabelle.reloadData()
            for ansicht in subviews where !(ansicht === leerhinweis) { ansicht.isHidden = true }
            return
        }
        for ansicht in subviews where !(ansicht === leerhinweis) { ansicht.isHidden = false }

        ueberschrift.stringValue = neuer.automatischErkannt
            ? "\(neuer.text)  (automatisch erkannt)"
            : neuer.text
        begriffFeld.stringValue = neuer.text
        kategorieWahl.selectItem(withTitle: neuer.kategorie.anzeigename)
        decknameFeld.stringValue = neuer.platzhalter
        zuruecksetzenKnopf.isEnabled = neuer.eigenerDeckname != nil

        fruehereZeile.stringValue = neuer.fruehereDecknamen.isEmpty
            ? "Noch nie umbenannt."
            : "Früher: \(neuer.fruehereDecknamen.joined(separator: ", ")). "
                + "Diese Namen lösen sich weiter auf, damit Antworten auf ältere Texte aufgehen."
        aliasTabelle.reloadData()
    }

    private func melde(_ text: String?) {
        meldung.stringValue = text ?? ""
        meldung.isHidden = text == nil
    }

    /// Schickt einen Befehl nach oben und zeigt an, was dabei herauskam.
    private func schicke(_ befehl: Befehl) {
        melde(beiBefehl?(befehl))
    }

    // MARK: Aktionen

    @objc private func begriffGeaendert() {
        guard let eintrag, begriffFeld.stringValue != eintrag.text else { return }
        schicke(.begriff(begriffFeld.stringValue))
    }

    @objc private func kategorieGeaendert() {
        guard let roh = kategorieWahl.selectedItem?.representedObject as? String,
              let kategorie = Kategorie(rawValue: roh),
              kategorie != eintrag?.kategorie
        else { return }
        schicke(.kategorie(kategorie))
    }

    @objc private func decknameGeaendert() {
        guard let eintrag, decknameFeld.stringValue.uppercased() != eintrag.platzhalter else { return }
        schicke(.deckname(decknameFeld.stringValue))
    }

    @objc private func decknameZurueckgesetzt() {
        schicke(.decknameZuruecksetzen)
    }

    @objc private func aliasHinzufuegen() {
        guard let text = frageNachText(
            titel: "Weitere Schreibweise",
            erklaerung: "Wie steht derselbe Begriff sonst noch im Text? Etwa nur der Nachname.",
            vorgabe: ""
        ) else { return }
        schicke(.aliasNeu(text))
    }

    @objc private func aliasAendern() {
        guard let alias = gewaehlterAlias else { return }
        guard let text = frageNachText(
            titel: "Schreibweise ändern",
            erklaerung: "Der Buchstabe bleibt, damit der Platzhalter dasselbe meint.",
            vorgabe: alias.text
        ) else { return }
        schicke(.aliasText(alias.id, text))
    }

    @objc private func aliasLoeschen() {
        guard let alias = gewaehlterAlias else { return }
        schicke(.aliasLoeschen(alias.id))
    }

    @objc private func aliasHauptnennung() {
        guard let alias = gewaehlterAlias else { return }
        schicke(.aliasHauptnennung(alias.id))
    }

    private var gewaehlterAlias: Alias? {
        guard let eintrag, eintrag.aliase.indices.contains(aliasTabelle.selectedRow) else { return nil }
        return eintrag.aliase[aliasTabelle.selectedRow]
    }

    private func frageNachText(titel: String, erklaerung: String, vorgabe: String) -> String? {
        let meldung = NSAlert()
        meldung.messageText = titel
        meldung.informativeText = erklaerung
        meldung.addButton(withTitle: "Übernehmen")
        meldung.addButton(withTitle: "Abbrechen")

        let feld = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        feld.stringValue = vorgabe
        meldung.accessoryView = feld
        meldung.window.initialFirstResponder = feld

        guard meldung.runModal() == .alertFirstButtonReturn else { return nil }
        let text = feld.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

extension EintragEditor: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { eintrag?.aliase.count ?? 0 }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let eintrag, eintrag.aliase.indices.contains(row) else { return nil }
        let alias = eintrag.aliase[row]

        let text = NSTextField(labelWithString: alias.text)
        text.font = .systemFont(ofSize: 12)
        text.lineBreakMode = .byTruncatingTail

        let platzhalter = NSTextField(labelWithString: eintrag.platzhalter(fuer: alias))
        platzhalter.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        platzhalter.textColor = .secondaryLabelColor

        let zeile = NSStackView(views: [text, platzhalter])
        zeile.orientation = .horizontal
        zeile.spacing = 8
        zeile.translatesAutoresizingMaskIntoConstraints = false

        let zelle = NSTableCellView()
        zelle.addSubview(zeile)
        NSLayoutConstraint.activate([
            zeile.leadingAnchor.constraint(equalTo: zelle.leadingAnchor, constant: 4),
            zeile.trailingAnchor.constraint(lessThanOrEqualTo: zelle.trailingAnchor, constant: -4),
            zeile.centerYAnchor.constraint(equalTo: zelle.centerYAnchor),
        ])
        return zelle
    }
}
