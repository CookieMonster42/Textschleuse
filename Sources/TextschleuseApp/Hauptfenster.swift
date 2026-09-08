import AppKit
import TextschleuseCore

/// Das Fenster für alle, die nicht über Kurzbefehle arbeiten wollen.
///
/// Es zeigt dieselben Arbeitsflächen wie die Popups, aber mit einem Feld zum
/// Einfügen davor und Knöpfen statt Tasten. Jeder Knopf sagt in seinem
/// Hilfetext, welche Taste dasselbe macht — wer will, wächst so in die
/// Tastatur hinein.
final class Hauptfenster: NSWindowController {

    private static var offen: Hauptfenster?

    /// Liefert das Wörterbuch und nimmt Änderungen entgegen. Das Fenster hält
    /// keinen eigenen Stand, sonst liefen zwei Wörterbücher auseinander.
    private let woerterbuch: () -> Woerterbuch
    private let beimSchuetzen: (Analyse, Bool) -> Void
    private let beimZurueckdrehen: (String) -> Void
    private let sitzungsZuordnung: () -> [String: String]

    private let reiter = NSTabView()
    private var schutzAnsicht: SchutzAnsicht?
    private var rueckwegAnsicht: RueckwegAnsicht?

    private let schutzEingabe = Eingabeflaeche(
        titel: "Text einfügen, der geschützt werden soll",
        knopf: "Prüfen"
    )
    private let rueckwegEingabe = Eingabeflaeche(
        titel: "KI-Antwort einfügen, deren Platzhalter zurückgedreht werden sollen",
        knopf: "Zurückdrehen"
    )
    private let schutzBehaelter = NSView()
    private let rueckwegBehaelter = NSView()

    static func zeige(
        woerterbuch: @escaping () -> Woerterbuch,
        sitzungsZuordnung: @escaping () -> [String: String],
        beimSchuetzen: @escaping (Analyse, Bool) -> Void,
        beimZurueckdrehen: @escaping (String) -> Void
    ) {
        if let vorhandenes = offen {
            vorhandenes.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let fenster = Hauptfenster(
            woerterbuch: woerterbuch,
            sitzungsZuordnung: sitzungsZuordnung,
            beimSchuetzen: beimSchuetzen,
            beimZurueckdrehen: beimZurueckdrehen
        )
        offen = fenster
        fenster.showWindow(nil)
        fenster.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init(
        woerterbuch: @escaping () -> Woerterbuch,
        sitzungsZuordnung: @escaping () -> [String: String],
        beimSchuetzen: @escaping (Analyse, Bool) -> Void,
        beimZurueckdrehen: @escaping (String) -> Void
    ) {
        self.woerterbuch = woerterbuch
        self.sitzungsZuordnung = sitzungsZuordnung
        self.beimSchuetzen = beimSchuetzen
        self.beimZurueckdrehen = beimZurueckdrehen

        let fenster = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        fenster.title = "Textschleuse"
        fenster.setFrameAutosaveName("textschleuse.hauptfenster")
        fenster.center()
        super.init(window: fenster)

        fenster.delegate = self
        baueOberflaeche()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }

    private func baueOberflaeche() {
        schutzEingabe.beiAusloesen = { [weak self] text in self?.pruefe(text) }
        rueckwegEingabe.beiAusloesen = { [weak self] text in self?.dreheZurueck(text) }

        for (behaelter, eingabe) in [
            (schutzBehaelter, schutzEingabe),
            (rueckwegBehaelter, rueckwegEingabe),
        ] {
            eingabe.translatesAutoresizingMaskIntoConstraints = false
            behaelter.addSubview(eingabe)
            NSLayoutConstraint.activate([
                eingabe.topAnchor.constraint(equalTo: behaelter.topAnchor),
                eingabe.leadingAnchor.constraint(equalTo: behaelter.leadingAnchor),
                eingabe.trailingAnchor.constraint(equalTo: behaelter.trailingAnchor),
                eingabe.bottomAnchor.constraint(equalTo: behaelter.bottomAnchor),
            ])
        }

        let schuetzen = NSTabViewItem(identifier: "schuetzen")
        schuetzen.label = "Schützen"
        schuetzen.view = schutzBehaelter

        let zurueck = NSTabViewItem(identifier: "rueckweg")
        zurueck.label = "Zurückdrehen"
        zurueck.view = rueckwegBehaelter

        reiter.addTabViewItem(schuetzen)
        reiter.addTabViewItem(zurueck)
        reiter.translatesAutoresizingMaskIntoConstraints = false

        let inhalt = NSView()
        inhalt.addSubview(reiter)
        NSLayoutConstraint.activate([
            reiter.topAnchor.constraint(equalTo: inhalt.topAnchor, constant: 12),
            reiter.leadingAnchor.constraint(equalTo: inhalt.leadingAnchor, constant: 12),
            reiter.trailingAnchor.constraint(equalTo: inhalt.trailingAnchor, constant: -12),
            reiter.bottomAnchor.constraint(equalTo: inhalt.bottomAnchor, constant: -12),
        ])
        window?.contentView = inhalt
    }

    // MARK: Schützen

    /// Holt sich, was in der Zwischenablage liegt, und prüft es sofort. Der
    /// Weg für alle, die den Kurzbefehl nicht benutzen wollen.
    func ausZwischenablage() {
        reiter.selectTabViewItem(at: 0)
        guard let text = Zwischenablage.lies(), !text.isEmpty else {
            zurueckZurEingabe()
            schutzEingabe.melde("In der Zwischenablage steht kein Text.")
            return
        }
        pruefe(text)
    }

    private func pruefe(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            schutzEingabe.melde("Da ist kein Text.")
            return
        }

        let analyse = Schleuse.analysiere(text, woerterbuch: woerterbuch())
        if let vorhanden = schutzAnsicht {
            vorhanden.setze(analyse: analyse)
        } else {
            let ansicht = SchutzAnsicht(analyse: analyse)
            ansicht.beiUebernahme = { [weak self] analyse, merken in
                self?.beimSchuetzen(analyse, merken)
                self?.schutzEingabe.melde("In die Zwischenablage gelegt. Jetzt im KI-Tool einfügen.")
            }
            ansicht.beiAbbruch = { [weak self] in self?.zurueckZurEingabe() }
            schutzAnsicht = ansicht
        }
        zeige(schutzAnsicht, in: schutzBehaelter, statt: schutzEingabe)
        window?.makeFirstResponder(schutzAnsicht)
    }

    private func zurueckZurEingabe() {
        zeige(schutzEingabe, in: schutzBehaelter, statt: schutzAnsicht)
        schutzAnsicht = nil
    }

    // MARK: Rückweg

    private func dreheZurueck(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            rueckwegEingabe.melde("Da ist kein Text.")
            return
        }

        let ergebnis = Rueckweg.analysiere(
            text,
            woerterbuch: woerterbuch(),
            unbekannte: sitzungsZuordnung()
        )
        if let vorhanden = rueckwegAnsicht {
            vorhanden.setze(ergebnis: ergebnis)
        } else {
            let ansicht = RueckwegAnsicht(
                ergebnis: ergebnis,
                woerterbuch: woerterbuch(),
                unbekannte: sitzungsZuordnung()
            )
            ansicht.beiUebernahme = { [weak self] fertig in
                self?.beimZurueckdrehen(fertig)
                self?.rueckwegEingabe.melde("In die Zwischenablage gelegt.")
            }
            ansicht.beiAbbruch = { [weak self] in
                guard let self else { return }
                self.zeige(self.rueckwegEingabe, in: self.rueckwegBehaelter, statt: self.rueckwegAnsicht)
                self.rueckwegAnsicht = nil
            }
            rueckwegAnsicht = ansicht
        }
        zeige(rueckwegAnsicht, in: rueckwegBehaelter, statt: rueckwegEingabe)
        window?.makeFirstResponder(rueckwegAnsicht)
    }

    // MARK: Umschalten

    private func zeige(_ neue: NSView?, in behaelter: NSView, statt alte: NSView?) {
        guard let neue else { return }
        alte?.removeFromSuperview()
        guard neue.superview !== behaelter else { return }
        neue.translatesAutoresizingMaskIntoConstraints = false
        behaelter.addSubview(neue)
        NSLayoutConstraint.activate([
            neue.topAnchor.constraint(equalTo: behaelter.topAnchor),
            neue.leadingAnchor.constraint(equalTo: behaelter.leadingAnchor),
            neue.trailingAnchor.constraint(equalTo: behaelter.trailingAnchor),
            neue.bottomAnchor.constraint(equalTo: behaelter.bottomAnchor),
        ])
    }
}

extension Hauptfenster: NSWindowDelegate {

    func windowWillClose(_ meldung: Notification) {
        Hauptfenster.offen = nil
    }
}

/// Das Feld zum Einfügen, mit Knopf daneben.
///
/// Der Text liegt in einer editierbaren Ansicht statt in einem Feld, damit
/// mehrzeilige Mails Platz haben und ⌘V ohne Umweg funktioniert.
final class Eingabeflaeche: NSView {

    var beiAusloesen: ((String) -> Void)?

    private let flaeche = Textflaeche.bauen()
    private let ueberschrift: NSTextField
    private let ausloeser: NSButton
    private let ausZwischenablage = NSButton()
    private let meldung = NSTextField(labelWithString: "")

    init(titel: String, knopf: String) {
        ueberschrift = NSTextField(labelWithString: titel)
        ausloeser = NSButton(title: knopf, target: nil, action: nil)
        super.init(frame: .zero)

        ueberschrift.font = .systemFont(ofSize: 13, weight: .semibold)

        // Die Textfläche ist sonst nur zum Lesen da; hier soll man tippen.
        flaeche.text.isEditable = true
        flaeche.text.font = .systemFont(ofSize: 13)
        flaeche.text.isAutomaticQuoteSubstitutionEnabled = false
        flaeche.text.isRichText = false
        flaeche.text.allowsUndo = true

        ausloeser.bezelStyle = .rounded
        ausloeser.keyEquivalent = "\r"
        ausloeser.target = self
        ausloeser.action = #selector(ausgeloest)

        ausZwischenablage.title = "Aus Zwischenablage einfügen"
        ausZwischenablage.bezelStyle = .rounded
        ausZwischenablage.target = self
        ausZwischenablage.action = #selector(zwischenablageHolen)
        ausZwischenablage.toolTip = "Nimmt, was gerade kopiert ist"

        meldung.font = .systemFont(ofSize: 11)
        meldung.textColor = .secondaryLabelColor

        let knopfleiste = NSStackView(views: [ausZwischenablage, ausloeser, meldung])
        knopfleiste.orientation = .horizontal
        knopfleiste.spacing = 8
        knopfleiste.translatesAutoresizingMaskIntoConstraints = false

        let hinweis = NSTextField(wrappingLabelWithString:
            "Läuft komplett auf diesem Rechner. Es geht nichts ins Netz. "
            + "Der Kurzbefehl ⌃⌥⌘S macht dasselbe, ohne dieses Fenster zu öffnen.")
        hinweis.font = .systemFont(ofSize: 11)
        hinweis.textColor = .tertiaryLabelColor

        let stapel = NSStackView(views: [ueberschrift, flaeche.rolle, knopfleiste, hinweis])
        stapel.orientation = .vertical
        stapel.spacing = 10
        stapel.alignment = .leading
        stapel.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stapel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stapel)

        ueberschrift.setContentHuggingPriority(.required, for: .vertical)
        knopfleiste.setContentHuggingPriority(.required, for: .vertical)
        hinweis.setContentHuggingPriority(.required, for: .vertical)

        NSLayoutConstraint.activate([
            stapel.topAnchor.constraint(equalTo: topAnchor),
            stapel.leadingAnchor.constraint(equalTo: leadingAnchor),
            stapel.trailingAnchor.constraint(equalTo: trailingAnchor),
            stapel.bottomAnchor.constraint(equalTo: bottomAnchor),
            flaeche.rolle.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -32),
            flaeche.rolle.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }

    func melde(_ text: String) {
        meldung.stringValue = text
    }

    /// Für den Selbsttest: Text setzen und auslösen ohne Tastatur.
    func setzeText(_ text: String) { flaeche.text.string = text }

    func loeseAus() { ausgeloest() }

    @objc private func ausgeloest() {
        meldung.stringValue = ""
        beiAusloesen?(flaeche.text.string)
    }

    @objc private func zwischenablageHolen() {
        guard let text = Zwischenablage.lies(), !text.isEmpty else {
            melde("In der Zwischenablage steht kein Text.")
            return
        }
        flaeche.text.string = text
        melde("")
        ausgeloest()
    }
}
