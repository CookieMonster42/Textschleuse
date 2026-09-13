import AppKit
import TextschleuseCore

/// Das Fenster für alle, die nicht über Kurzbefehle arbeiten wollen.
///
/// Ein Textfeld, zwei Richtungen. Der Umschalter oben sagt, was mit dem
/// Text geschehen soll: Schützen oder Zurückdrehen. Beim Umschalten bleibt
/// der Text stehen und wird in der anderen Richtung geprüft — es sind nicht
/// zwei Fenster mit zwei Texten, sondern eines. Nur die Verläufe sind
/// getrennt, weil eine Anfrage und ihre Antwort verschiedene Texte sind.
final class Hauptfenster: NSWindowController {

    enum Modus: Int {
        case schuetzen = 0
        case zurueckdrehen = 1
    }

    private static var offen: Hauptfenster?

    /// Liefert das Wörterbuch und nimmt Änderungen entgegen. Das Fenster hält
    /// keinen eigenen Stand, sonst liefen zwei Wörterbücher auseinander.
    private let woerterbuch: () -> Woerterbuch
    private let beimSchuetzen: (Analyse, Bool) -> Void
    private let beimZurueckdrehen: (String) -> Void
    private let beimWoerterbuch: (Woerterbuch) -> Void
    /// Die Texte dieser Sitzung. Geteilt mit den Popups, damit beide Wege
    /// denselben Stand sehen.
    private let sitzung: Sitzung
    /// Die Vorgänge, an denen dieses Fenster gerade arbeitet — einer je
    /// Richtung.
    private var laufenderVorgang: UUID?
    private var laufenderRueckweg: UUID?

    private(set) var modus: Modus = .schuetzen
    private let modusWahl = NSSegmentedControl(
        labels: ["Schützen", "Zurückdrehen"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let arbeitsflaeche = NSView()
    private let schutzAnsicht: SchutzAnsicht
    private let rueckwegAnsicht: RueckwegAnsicht

    private let verlaufWahl = NSPopUpButton()
    private let verlaufEtikett = NSTextField(labelWithString: "Diese Sitzung")
    /// Das Wörterbuch als feste Spalte rechts. Es hängt am Fenster, nicht an
    /// der Arbeitsfläche.
    private var woerterbuchSpalte: WoerterbuchAnsicht?
    /// Das Tastenkürzel-Blatt kommt einmal je Fensterleben beim Öffnen.
    private var startblattGezeigt = false

    static func zeige(
        woerterbuch: @escaping () -> Woerterbuch,
        sitzung: Sitzung,
        beimSchuetzen: @escaping (Analyse, Bool) -> Void,
        beimZurueckdrehen: @escaping (String) -> Void,
        beimWoerterbuch: @escaping (Woerterbuch) -> Void
    ) {
        if let vorhandenes = offen {
            // Beim Wiederaufmachen den neuesten Stand zeigen — womöglich hat
            // seither jemand im Popup gearbeitet.
            vorhandenes.zeigeNeuesten()
            vorhandenes.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let fenster = Hauptfenster(
            woerterbuch: woerterbuch,
            sitzung: sitzung,
            beimSchuetzen: beimSchuetzen,
            beimZurueckdrehen: beimZurueckdrehen,
            beimWoerterbuch: beimWoerterbuch
        )
        offen = fenster
        fenster.showWindow(nil)
        fenster.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init(
        woerterbuch: @escaping () -> Woerterbuch,
        sitzung: Sitzung,
        beimSchuetzen: @escaping (Analyse, Bool) -> Void,
        beimZurueckdrehen: @escaping (String) -> Void,
        beimWoerterbuch: @escaping (Woerterbuch) -> Void = { _ in }
    ) {
        self.woerterbuch = woerterbuch
        self.beimWoerterbuch = beimWoerterbuch
        self.sitzung = sitzung
        self.beimSchuetzen = beimSchuetzen
        self.beimZurueckdrehen = beimZurueckdrehen

        let buch = woerterbuch()
        schutzAnsicht = SchutzAnsicht(analyse: Schleuse.analysiere("", woerterbuch: buch))
        rueckwegAnsicht = RueckwegAnsicht(
            ergebnis: Rueckweg.analysiere("", woerterbuch: buch, unbekannte: sitzung.unbekannte),
            woerterbuch: buch,
            unbekannte: sitzung.unbekannte
        )

        let fenster = NSWindow(
            contentRect: NSRect(origin: .zero, size: Hauptfenster.startgroesse()),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        fenster.title = "Textschleuse"
        // Das ist kein Wunschwert, sondern das, was das Layout wirklich
        // hergibt: Arbeitsfläche 700, Wörterbuchspalte 400, Ränder.
        fenster.minSize = NSSize(width: 1200, height: 720)
        // Neuer Name, weil die alte gemerkte Größe 1620 breit war und den
        // Bildschirm gefüllt hat. Unter dem alten Namen käme sie zurück.
        fenster.setFrameAutosaveName("textschleuse.hauptfenster.2")
        fenster.center()
        super.init(window: fenster)

        fenster.delegate = self
        baueOberflaeche()
        verdrahteAnsichten()
        zeigeNeuesten()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }

    /// Beim ersten Öffnen liegt die Tastenkürzel-Übersicht obenauf, solange
    /// das in ihr angehakt ist.
    override func showWindow(_ absender: Any?) {
        super.showWindow(absender)
        guard !startblattGezeigt else { return }
        startblattGezeigt = true
        Tastenkuerzel.zeigeBeimStart(ueber: window)
    }

    /// Wunschmaß, aber nie größer als der Bildschirm hergibt. Ein Fenster, das
    /// beim Öffnen alles verdeckt, zwingt dich zum Verkleinern, bevor du
    /// arbeiten kannst.
    static func startgroesse(
        auf sichtbar: NSRect? = nil
    ) -> NSSize {
        let flaeche = sichtbar ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 860)
        return NSSize(
            width: max(1200, min(1240, flaeche.width - 160)),
            // Die Höhe darf großzügiger sein als die Breite: davon lebt die
            // Wörterbuchliste, und zu breit war das Fenster, nicht zu hoch.
            height: max(720, min(820, flaeche.height - 100))
        )
    }

    // MARK: Aufbau

    private func baueOberflaeche() {
        modusWahl.selectedSegment = 0
        modusWahl.target = self
        modusWahl.action = #selector(modusGewaehlt)
        modusWahl.segmentStyle = .rounded
        modusWahl.setToolTip("Namen durch Decknamen ersetzen", forSegment: 0)
        modusWahl.setToolTip("Decknamen in einer Antwort wieder auflösen", forSegment: 1)
        modusWahl.translatesAutoresizingMaskIntoConstraints = false

        verlaufEtikett.font = .systemFont(ofSize: 11)
        verlaufEtikett.textColor = .secondaryLabelColor
        verlaufWahl.target = self
        verlaufWahl.action = #selector(verlaufGewaehlt)
        verlaufWahl.toolTip = "Die Texte dieser Sitzung in dieser Richtung. Nach dem Beenden sind sie weg."
        // Der längste Eintrag darf das Fenster nicht breiter zwingen: lieber
        // wird der Titel abgeschnitten.
        verlaufWahl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        (verlaufWahl.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail

        let kopfzeile = NSStackView(views: [modusWahl, verlaufEtikett, verlaufWahl])
        kopfzeile.orientation = .horizontal
        kopfzeile.spacing = 8
        kopfzeile.setCustomSpacing(20, after: modusWahl)
        kopfzeile.translatesAutoresizingMaskIntoConstraints = false

        arbeitsflaeche.translatesAutoresizingMaskIntoConstraints = false

        let spalte = WoerterbuchAnsicht(
            woerterbuch: woerterbuch(),
            schmal: true,
            beimSichern: { [weak self] geaendert in
                guard let self else { return }
                self.beimWoerterbuch(geaendert)
                // Beide Richtungen müssen nachziehen: was gerade gemerkt
                // wurde, gilt ab jetzt auch für den laufenden Text.
                self.schutzAnsicht.uebernimmWoerterbuch(geaendert)
                self.rueckwegAnsicht.setze(woerterbuch: geaendert)
            },
            beimExportieren: { _, _ in }
        )
        spalte.translatesAutoresizingMaskIntoConstraints = false
        woerterbuchSpalte = spalte

        let trenner = NSBox()
        trenner.boxType = .separator
        trenner.translatesAutoresizingMaskIntoConstraints = false

        let inhalt = NSView()
        let anteil = spalte.widthAnchor.constraint(equalTo: inhalt.widthAnchor, multiplier: 0.33)
        anteil.priority = .defaultHigh
        inhalt.addSubview(kopfzeile)
        inhalt.addSubview(arbeitsflaeche)
        inhalt.addSubview(trenner)
        inhalt.addSubview(spalte)
        NSLayoutConstraint.activate([
            kopfzeile.topAnchor.constraint(equalTo: inhalt.topAnchor, constant: 12),
            kopfzeile.leadingAnchor.constraint(equalTo: inhalt.leadingAnchor, constant: 12),
            kopfzeile.trailingAnchor.constraint(lessThanOrEqualTo: trenner.leadingAnchor, constant: -12),
            verlaufWahl.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
            verlaufWahl.widthAnchor.constraint(lessThanOrEqualToConstant: 520),

            arbeitsflaeche.topAnchor.constraint(equalTo: kopfzeile.bottomAnchor, constant: 4),
            arbeitsflaeche.leadingAnchor.constraint(equalTo: inhalt.leadingAnchor),
            arbeitsflaeche.trailingAnchor.constraint(equalTo: trenner.leadingAnchor, constant: -12),
            arbeitsflaeche.bottomAnchor.constraint(equalTo: inhalt.bottomAnchor),

            trenner.topAnchor.constraint(equalTo: inhalt.topAnchor, constant: 12),
            trenner.bottomAnchor.constraint(equalTo: inhalt.bottomAnchor, constant: -12),
            trenner.widthAnchor.constraint(equalToConstant: 1),
            trenner.trailingAnchor.constraint(equalTo: spalte.leadingAnchor, constant: -12),

            spalte.topAnchor.constraint(equalTo: inhalt.topAnchor, constant: 12),
            spalte.trailingAnchor.constraint(equalTo: inhalt.trailingAnchor, constant: -12),
            spalte.bottomAnchor.constraint(equalTo: inhalt.bottomAnchor, constant: -12),
            // Ein Drittel statt starrer 540 Punkte: bei einem schmaleren
            // Fenster bliebe für den Text sonst kaum etwas übrig.
            spalte.widthAnchor.constraint(greaterThanOrEqualToConstant: 380),
            spalte.widthAnchor.constraint(lessThanOrEqualToConstant: 560),
            anteil,
        ])
        window?.contentView = inhalt
    }

    private func verdrahteAnsichten() {
        schutzAnsicht.beiUebernahme = { [weak self] analyse, merken in
            self?.beimSchuetzen(analyse, merken)
            self?.schutzAnsicht.meldeKopiert()
        }
        // ⎋ im Fenster: nichts. Der Text bleibt, wie er ist — ein Fenster
        // hat kein „Abbrechen", nur das Popup.
        schutzAnsicht.beiAbbruch = {}
        schutzAnsicht.beiAenderung = { [weak self] stand in
            guard let self else { return }
            if let kennung = self.laufenderVorgang {
                self.sitzung.aktualisiere(kennung, mit: stand)
            } else if !stand.original.isEmpty {
                // Der erste getippte Text ist ein neuer Vorgang.
                self.laufenderVorgang = self.sitzung.beginne(stand)
            }
            if self.modus == .schuetzen { self.aktualisiereVerlauf() }
            // Wächst das Wörterbuch beim Schützen, zeigt die Spalte es
            // sofort — nicht erst beim nächsten Öffnen.
            self.woerterbuchSpalte?.setze(woerterbuch: stand.woerterbuch)
            self.woerterbuchSpalte?.setze(imText: Set(stand.aktiveFunde.compactMap(\.eintragId)))
        }
        schutzAnsicht.beiWoerterbuchAenderung = { [weak self] geaendert in
            self?.beimWoerterbuch(geaendert)
            self?.woerterbuchSpalte?.setze(woerterbuch: geaendert)
            self?.rueckwegAnsicht.setze(woerterbuch: geaendert)
        }
        // Die Klappe braucht es hier nicht: das Wörterbuch steht schon als
        // feste Spalte rechts im Fenster.
        schutzAnsicht.verbergeKlappenknopf()

        rueckwegAnsicht.beiUebernahme = { [weak self] fertig in
            self?.beimZurueckdrehen(fertig)
        }
        rueckwegAnsicht.beiAbbruch = {}
        rueckwegAnsicht.beiAenderung = { [weak self] stand in
            guard let self else { return }
            if let kennung = self.laufenderRueckweg {
                self.sitzung.aktualisiereRueckweg(kennung, mit: stand.original)
            } else if !stand.original.isEmpty {
                self.laufenderRueckweg = self.sitzung.beginneRueckweg(stand.original)
            }
            if self.modus == .zurueckdrehen { self.aktualisiereVerlauf() }
        }
        rueckwegAnsicht.beiWoerterbuchAenderung = { [weak self] geaendert in
            self?.beimWoerterbuch(geaendert)
            self?.woerterbuchSpalte?.setze(woerterbuch: geaendert)
            self?.schutzAnsicht.uebernimmWoerterbuch(geaendert)
        }
    }

    // MARK: Richtung

    var aktuelleAnsicht: NSView {
        modus == .schuetzen ? schutzAnsicht : rueckwegAnsicht
    }

    /// Der Text, der gerade im Fenster steht — in beiden Richtungen derselbe.
    var aktuellerText: String {
        modus == .schuetzen ? schutzAnsicht.analyse.original : rueckwegAnsicht.ergebnis.original
    }

    @objc private func modusGewaehlt() {
        wechsle(zu: Modus(rawValue: modusWahl.selectedSegment) ?? .schuetzen)
    }

    /// Schaltet die Richtung um. Der Text bleibt; er wird nur in der anderen
    /// Richtung geprüft. Steht er dort schon, gibt es nichts zu tun.
    func wechsle(zu neuer: Modus) {
        guard neuer != modus else { return }
        let text = aktuellerText
        modus = neuer
        modusWahl.selectedSegment = neuer.rawValue

        switch neuer {
        case .schuetzen:
            if schutzAnsicht.analyse.original != text {
                pruefe(text)
            } else {
                zeige(schutzAnsicht)
            }
        case .zurueckdrehen:
            if rueckwegAnsicht.ergebnis.original != text {
                dreheZurueck(text)
            } else {
                zeige(rueckwegAnsicht)
            }
        }
        aktualisiereVerlauf()
    }

    // MARK: Schützen

    /// Holt sich, was in der Zwischenablage liegt, in die laufende Richtung.
    func ausZwischenablage() {
        if modus == .schuetzen {
            schutzAnsicht.aktionNeuerText(nil)
        } else {
            rueckwegAnsicht.aktionNeuerText(nil)
        }
    }

    /// Holt den neuesten Vorgang der Sitzung ins Fenster. Ohne das säße hier
    /// noch der Text von vorhin, während im Popup längst ein anderer läuft.
    func zeigeNeuesten() {
        if modus == .schuetzen, let neuester = sitzung.neuester, neuester.id != laufenderVorgang {
            laufenderVorgang = neuester.id
            zeigeAnalyse(neuester.analyse)
        } else {
            zeige(aktuelleAnsicht)
        }
        aktualisiereVerlauf()
    }

    private func pruefe(_ text: String) {
        let analyse = Schleuse.analysiere(text, woerterbuch: woerterbuch())
        laufenderVorgang = text.isEmpty ? nil : sitzung.beginne(analyse)
        zeigeAnalyse(analyse)
        aktualisiereVerlauf()
    }

    private func zeigeAnalyse(_ analyse: Analyse) {
        woerterbuchSpalte?.setze(imText: Set(analyse.aktiveFunde.compactMap(\.eintragId)))
        schutzAnsicht.setze(analyse: analyse)
        zeige(schutzAnsicht)
    }

    // MARK: Rückweg

    private func dreheZurueck(_ text: String) {
        let ergebnis = Rueckweg.analysiere(
            text,
            woerterbuch: woerterbuch(),
            unbekannte: sitzung.unbekannte
        )
        laufenderRueckweg = text.isEmpty ? nil : sitzung.beginneRueckweg(text)
        rueckwegAnsicht.setze(ergebnis: ergebnis, woerterbuch: woerterbuch(), unbekannte: sitzung.unbekannte)
        zeige(rueckwegAnsicht)
        aktualisiereVerlauf()
    }

    // MARK: Verlauf

    private func aktualisiereVerlauf() {
        let format = DateFormatter()
        format.dateStyle = .none
        format.timeStyle = .short

        verlaufWahl.removeAllItems()
        let eintraege: [(UUID, Date, String)] = modus == .schuetzen
            ? sitzung.vorgaenge.map { ($0.id, $0.zeitpunkt, $0.vorschau) }
            : sitzung.rueckwegVorgaenge.map { ($0.id, $0.zeitpunkt, $0.vorschau) }
        for (kennung, zeitpunkt, vorschau) in eintraege {
            verlaufWahl.addItem(withTitle: "\(format.string(from: zeitpunkt))  ·  \(vorschau)")
            verlaufWahl.lastItem?.representedObject = kennung
        }
        if eintraege.isEmpty {
            verlaufWahl.addItem(withTitle: "Noch nichts bearbeitet")
        }
        verlaufWahl.isEnabled = !eintraege.isEmpty
        verlaufEtikett.stringValue = eintraege.count > 1
            ? "Diese Sitzung (\(eintraege.count))"
            : "Diese Sitzung"

        let laufend = modus == .schuetzen ? laufenderVorgang : laufenderRueckweg
        if let laufend, let index = eintraege.firstIndex(where: { $0.0 == laufend }) {
            verlaufWahl.selectItem(at: index)
        }
    }

    @objc private func verlaufGewaehlt() {
        guard let kennung = verlaufWahl.selectedItem?.representedObject as? UUID else { return }
        switch modus {
        case .schuetzen:
            guard kennung != laufenderVorgang, let vorgang = sitzung.vorgang(kennung) else { return }
            laufenderVorgang = kennung
            zeigeAnalyse(vorgang.analyse)
        case .zurueckdrehen:
            guard kennung != laufenderRueckweg, let vorgang = sitzung.rueckwegVorgang(kennung) else { return }
            laufenderRueckweg = kennung
            rueckwegAnsicht.setze(
                ergebnis: Rueckweg.analysiere(
                    vorgang.text,
                    woerterbuch: woerterbuch(),
                    unbekannte: sitzung.unbekannte
                ),
                woerterbuch: woerterbuch(),
                unbekannte: sitzung.unbekannte
            )
            zeige(rueckwegAnsicht)
        }
    }

    // MARK: Umschalten

    private func zeige(_ neue: NSView) {
        for alte in arbeitsflaeche.subviews where alte !== neue {
            alte.removeFromSuperview()
        }
        if neue.superview !== arbeitsflaeche {
            neue.translatesAutoresizingMaskIntoConstraints = false
            arbeitsflaeche.addSubview(neue)
            NSLayoutConstraint.activate([
                neue.topAnchor.constraint(equalTo: arbeitsflaeche.topAnchor),
                neue.leadingAnchor.constraint(equalTo: arbeitsflaeche.leadingAnchor),
                neue.trailingAnchor.constraint(equalTo: arbeitsflaeche.trailingAnchor),
                neue.bottomAnchor.constraint(equalTo: arbeitsflaeche.bottomAnchor),
            ])
        }
        // Fokus dorthin, wo es weitergeht: in die Liste, sonst in den Text.
        if neue === schutzAnsicht {
            schutzAnsicht.fokussiereFundstellen()
        } else {
            rueckwegAnsicht.fokussiereFundstellen()
        }
    }
}

extension Hauptfenster: NSWindowDelegate {

    func windowWillClose(_ meldung: Notification) {
        Hauptfenster.offen = nil
    }
}
