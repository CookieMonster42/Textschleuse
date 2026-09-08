import AppKit
import TextschleuseCore

/// Das Fenster, das nach dem Schutz-Kurzbefehl aufgeht.
///
/// Es zeigt den Text mit den Fundstellen als Chips. Grün heißt geregelt, rot
/// heißt geraten. Enter legt das Ergebnis in die Zwischenablage.
final class SchutzPopup: TastaturPanel {

    enum Ausgang {
        /// Übernommen. `merken` heißt: die bestätigten Vermutungen wandern ins
        /// Wörterbuch.
        case uebernommen(Analyse, merken: Bool)
        case abgebrochen
    }

    private var analyse: Analyse
    private let abschluss: (Ausgang) -> Void

    private var auswahl: Int = 0
    private var reihenfolge: [UUID] = []
    private var bereiche: [UUID: NSRange] = [:]

    private let kopfzeile = NSTextField(labelWithString: "")
    private let regelzeile = NSTextField(labelWithString: "")
    private let textAnsicht = NSTextView()
    private let rollflaeche = NSScrollView()
    private let knopfleiste = NSStackView()
    private let fusszeile = NSTextField(labelWithString: "")

    init(analyse: Analyse, abschluss: @escaping (Ausgang) -> Void) {
        self.analyse = analyse
        self.abschluss = abschluss

        let bildschirm = TastaturPanel.bildschirmUnterMaus
        let maximal = TastaturPanel.maximaleGroesse(auf: bildschirm)
        super.init(groesse: NSSize(width: min(860, maximal.width), height: min(600, maximal.height)))

        baueOberflaeche()
        aktualisiere()
    }

    // MARK: Aufbau

    private func baueOberflaeche() {
        kopfzeile.font = .systemFont(ofSize: 15, weight: .semibold)
        regelzeile.font = .systemFont(ofSize: 12)
        regelzeile.textColor = .secondaryLabelColor
        regelzeile.lineBreakMode = .byTruncatingTail

        textAnsicht.isEditable = false
        textAnsicht.isSelectable = true
        textAnsicht.drawsBackground = false
        textAnsicht.textContainerInset = NSSize(width: 10, height: 10)
        textAnsicht.delegate = self
        textAnsicht.linkTextAttributes = [:]
        textAnsicht.isAutomaticLinkDetectionEnabled = false

        rollflaeche.documentView = textAnsicht
        rollflaeche.hasVerticalScroller = true
        rollflaeche.drawsBackground = true
        rollflaeche.borderType = .noBorder
        rollflaeche.wantsLayer = true
        rollflaeche.layer?.cornerRadius = 8

        knopfleiste.orientation = .horizontal
        knopfleiste.spacing = 6
        baueKnoepfe()

        fusszeile.font = .systemFont(ofSize: 11)
        fusszeile.textColor = .secondaryLabelColor
        fusszeile.stringValue =
            "⏎ Kopieren · ⌘⏎ Kopieren und merken · ⎋ Abbrechen · ↑ ↓ Fundstelle · ⌫ Verwerfen"

        let stapel = NSStackView(views: [kopfzeile, regelzeile, rollflaeche, knopfleiste, fusszeile])
        stapel.orientation = .vertical
        stapel.spacing = 10
        stapel.alignment = .leading
        stapel.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        stapel.setHuggingPriority(.defaultLow, for: .vertical)

        contentView = stapel
        stapel.translatesAutoresizingMaskIntoConstraints = false
        if let inhalt = contentView {
            NSLayoutConstraint.activate([
                rollflaeche.leadingAnchor.constraint(equalTo: stapel.leadingAnchor, constant: 18),
                rollflaeche.trailingAnchor.constraint(equalTo: stapel.trailingAnchor, constant: -18),
                kopfzeile.leadingAnchor.constraint(equalTo: stapel.leadingAnchor, constant: 18),
                regelzeile.leadingAnchor.constraint(equalTo: stapel.leadingAnchor, constant: 18),
                inhalt.widthAnchor.constraint(greaterThanOrEqualToConstant: 640),
            ])
        }
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
        verwerfen.bezelStyle = .rounded
        verwerfen.controlSize = .small
        verwerfen.toolTip = "Rücktaste macht dasselbe"
        knopfleiste.addArrangedSubview(verwerfen)

        let gruppe = NSButton(title: "Zur Gruppe (G)", target: self, action: #selector(gruppeGeklickt))
        gruppe.bezelStyle = .rounded
        gruppe.controlSize = .small
        gruppe.toolTip = "Taste G macht dasselbe"
        knopfleiste.addArrangedSubview(gruppe)
    }

    // MARK: Darstellung

    private func aktualisiere() {
        reihenfolge = analyse.funde
            .filter { !$0.verworfen }
            .sorted { $0.bereich.location < $1.bereich.location }
            .map(\.id)
        if reihenfolge.isEmpty {
            auswahl = 0
        } else {
            auswahl = min(auswahl, reihenfolge.count - 1)
        }

        let gewaehlt = reihenfolge.indices.contains(auswahl) ? reihenfolge[auswahl] : nil
        let aufbau = Chiptext.aufbauen(analyse: analyse, ausgewaehlt: gewaehlt)
        bereiche = aufbau.bereiche
        textAnsicht.textStorage?.setAttributedString(aufbau.text)

        let gesamt = analyse.aktiveFunde.count
        let offen = analyse.ungeprueft.count
        kopfzeile.stringValue = offen == 0
            ? "\(gesamt) Fundstellen, alle geprüft"
            : "\(gesamt - offen) von \(gesamt) geprüft, \(offen) offen"

        let zusammenfassung = analyse.regelZusammenfassung
            .map { "\($0.anzahl) \($0.kategorie.anzeigename)" }
            .joined(separator: ", ")
        regelzeile.stringValue = zusammenfassung.isEmpty
            ? "Keine Regeltreffer."
            : "Ohne Nachfrage ersetzt: \(zusammenfassung)."

        if let gewaehlt, let bereich = bereiche[gewaehlt] {
            textAnsicht.scrollRangeToVisible(bereich)
        }
        aktualisiereKnoepfe()
    }

    private func aktualisiereKnoepfe() {
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
                knopf.isEnabled = fund != nil
            }
        }
    }

    private var aktuellerFund: Fund? {
        guard reihenfolge.indices.contains(auswahl) else { return nil }
        let kennung = reihenfolge[auswahl]
        return analyse.funde.first { $0.id == kennung }
    }

    // MARK: Tastatur

    override func keyDown(with ereignis: NSEvent) {
        let zusatz = ereignis.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch ereignis.keyCode {
        case 36, 76:  // Return, Enter
            uebernehmen(merken: zusatz.contains(.command))
            return
        case 53:  // Escape
            abbrechen()
            return
        case 126:  // Pfeil hoch
            waehle(auswahl - 1)
            return
        case 125:  // Pfeil runter
            waehle(auswahl + 1)
            return
        case 51, 117:  // Rücktaste, Entfernen
            verwerfeAktuellen()
            return
        default:
            break
        }

        guard let zeichen = ereignis.charactersIgnoringModifiers?.lowercased() else {
            super.keyDown(with: ereignis)
            return
        }

        if let ziffer = Int(zeichen), (1...Kategorie.schnellwahl.count).contains(ziffer) {
            setzeKategorie(Kategorie.schnellwahl[ziffer - 1])
            return
        }
        if zeichen == "g" {
            gruppeUebernehmen()
            return
        }
        super.keyDown(with: ereignis)
    }

    private func waehle(_ index: Int) {
        guard !reihenfolge.isEmpty else { return }
        auswahl = (index + reihenfolge.count) % reihenfolge.count
        aktualisiere()
    }

    // MARK: Aktionen

    @objc private func kategorieGeklickt(_ absender: NSButton) {
        guard Kategorie.schnellwahl.indices.contains(absender.tag) else { return }
        setzeKategorie(Kategorie.schnellwahl[absender.tag])
    }

    @objc private func verwerfenGeklickt() { verwerfeAktuellen() }

    @objc private func gruppeGeklickt() { gruppeUebernehmen() }

    private func setzeKategorie(_ kategorie: Kategorie) {
        guard let fund = aktuellerFund else { return }
        Schleuse.bestaetige(fundId: fund.id, als: kategorie, in: &analyse)
        weiterZurNaechstenLuecke()
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

    private func uebernehmen(merken: Bool) {
        abschluss(.uebernommen(analyse, merken: merken))
        schliesseUndGibFokusZurueck()
    }

    private func abbrechen() {
        abschluss(.abgebrochen)
        schliesseUndGibFokusZurueck()
    }
}

extension SchutzPopup: NSTextViewDelegate {

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
        let kennung = text.replacingOccurrences(of: "fund://", with: "")
        guard let uuid = UUID(uuidString: kennung),
              let index = reihenfolge.firstIndex(of: uuid)
        else { return false }
        auswahl = index
        aktualisiere()
        return true
    }
}
