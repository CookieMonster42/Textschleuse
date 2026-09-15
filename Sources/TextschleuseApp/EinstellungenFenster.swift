import AppKit
import Carbon.HIToolbox
import TextschleuseCore

/// Ein Feld, das eine Tastenkombination aufnimmt.
///
/// Anklicken, Kombination drücken, fertig. Es prüft dabei zweierlei: dass
/// überhaupt eine Zusatztaste dabei ist — ohne die würde der Kurzbefehl jede
/// Eingabe im ganzen System abfangen — und dass die Kombination nicht schon
/// von einem anderen Programm belegt ist.
final class Kurzbefehlfeld: NSView {

    /// Läuft, wenn eine gültige neue Kombination aufgenommen wurde.
    var beiAufnahme: ((Tastenkombination) -> Void)?

    private(set) var kombination: Tastenkombination
    private let knopf = NSButton()
    private let meldung = NSTextField(labelWithString: "")
    private var nimmtAuf = false
    private var beobachter: Any?

    init(_ kombination: Tastenkombination) {
        self.kombination = kombination
        super.init(frame: .zero)
        baueAuf()
        beschrifte()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }

    deinit {
        if let beobachter { NSEvent.removeMonitor(beobachter) }
    }

    private func baueAuf() {
        knopf.bezelStyle = .rounded
        knopf.target = self
        knopf.action = #selector(aufnahmeUmschalten)
        knopf.toolTip = "Anklicken, dann die gewünschte Tastenkombination drücken"

        meldung.font = .systemFont(ofSize: 11)
        meldung.textColor = .systemRed
        meldung.isHidden = true

        let stapel = NSStackView(views: [knopf, meldung])
        stapel.orientation = .horizontal
        stapel.spacing = 8
        stapel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stapel)
        NSLayoutConstraint.activate([
            stapel.topAnchor.constraint(equalTo: topAnchor),
            stapel.bottomAnchor.constraint(equalTo: bottomAnchor),
            stapel.leadingAnchor.constraint(equalTo: leadingAnchor),
            stapel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            knopf.widthAnchor.constraint(greaterThanOrEqualToConstant: 130),
        ])
    }

    private func beschrifte() {
        knopf.title = nimmtAuf ? "… drücken" : kombination.beschriftung
    }

    private func melde(_ text: String?) {
        meldung.stringValue = text ?? ""
        meldung.isHidden = text == nil
    }

    // MARK: Für den Selbsttest

    func aufnahmeFuerPruefung() { beginne() }

    func tasteFuerPruefung(code: UInt16, zusatz: NSEvent.ModifierFlags) {
        guard let ereignis = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: zusatz,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: code
        ) else { return }
        nimm(ereignis)
    }

    // MARK: Aufnehmen

    @objc private func aufnahmeUmschalten() {
        nimmtAuf ? beende() : beginne()
    }

    private func beginne() {
        nimmtAuf = true
        melde(nil)
        beschrifte()

        // Ein lokaler Mitschnitt statt `keyDown`: so kommen auch Kombinationen
        // an, die sonst ein Menü abfangen würde.
        beobachter = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ereignis in
            self?.nimm(ereignis)
            return nil
        }
    }

    private func beende() {
        nimmtAuf = false
        if let beobachter { NSEvent.removeMonitor(beobachter) }
        beobachter = nil
        beschrifte()
    }

    private func nimm(_ ereignis: NSEvent) {
        if ereignis.keyCode == UInt16(kVK_Escape) {
            beende()
            return
        }

        let zusatz = Tastenkombination.carbonFlags(aus: ereignis.modifierFlags)
        guard zusatz != 0 else {
            melde("Ohne ⌘, ⌥ oder ⌃ geht es nicht — sonst wäre jede Eingabe betroffen.")
            return
        }

        let neue = Tastenkombination(tastencode: UInt32(ereignis.keyCode), zusatztasten: zusatz)
        guard neue != kombination else {
            beende()
            return
        }
        guard Kurzbefehle.gemeinsam.istFrei(neue) else {
            melde("\(neue.beschriftung) ist schon belegt.")
            return
        }

        kombination = neue
        beende()
        melde(nil)
        beiAufnahme?(neue)
    }
}

/// Das Einstellungsfenster.
final class EinstellungenFenster: NSWindowController {

    private static var offen: EinstellungenFenster?

    private let beiKurzbefehlen: () -> Void
    private let beiDarstellung: (Bool) -> Void
    private var woerterbuch: Woerterbuch
    private let beimWoerterbuch: (Woerterbuch) -> Void
    private var freiliste: FreilisteAnsicht?
    private let seedFeld = NSTextField()
    private let seedMeldung = NSTextField(labelWithString: "")

    static func zeige(
        beiKurzbefehlen: @escaping () -> Void,
        beiDarstellung: @escaping (Bool) -> Void,
        woerterbuch: Woerterbuch = Woerterbuch(),
        beimWoerterbuch: @escaping (Woerterbuch) -> Void = { _ in }
    ) {
        if let vorhandenes = offen {
            vorhandenes.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let fenster = EinstellungenFenster(
            beiKurzbefehlen: beiKurzbefehlen,
            beiDarstellung: beiDarstellung,
            woerterbuch: woerterbuch,
            beimWoerterbuch: beimWoerterbuch
        )
        offen = fenster
        fenster.showWindow(nil)
        fenster.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init(
        beiKurzbefehlen: @escaping () -> Void,
        beiDarstellung: @escaping (Bool) -> Void,
        woerterbuch: Woerterbuch = Woerterbuch(),
        beimWoerterbuch: @escaping (Woerterbuch) -> Void = { _ in }
    ) {
        self.beiKurzbefehlen = beiKurzbefehlen
        self.beiDarstellung = beiDarstellung
        self.woerterbuch = woerterbuch
        self.beimWoerterbuch = beimWoerterbuch

        let fenster = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        fenster.title = "Einstellungen"
        fenster.center()
        super.init(window: fenster)
        fenster.delegate = self
        baueOberflaeche()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }

    private func baueOberflaeche() {
        let einstellungen = Einstellungen.gemeinsam

        let schuetzenFeld = Kurzbefehlfeld(einstellungen.kurzbefehlSchuetzen)
        schuetzenFeld.beiAufnahme = { [weak self] neue in
            Einstellungen.gemeinsam.kurzbefehlSchuetzen = neue
            self?.beiKurzbefehlen()
        }

        let rueckwegFeld = Kurzbefehlfeld(einstellungen.kurzbefehlRueckweg)
        rueckwegFeld.beiAufnahme = { [weak self] neue in
            Einstellungen.gemeinsam.kurzbefehlRueckweg = neue
            self?.beiKurzbefehlen()
        }

        let position = NSPopUpButton()
        for wahl in PopupPosition.allCases {
            position.addItem(withTitle: wahl.anzeigename)
            position.lastItem?.representedObject = wahl.rawValue
        }
        position.selectItem(withTitle: einstellungen.popupPosition.anzeigename)
        position.target = self
        position.action = #selector(positionGewaehlt(_:))

        let hinweise = NSButton(
            checkboxWithTitle: "KI-Hinweis mitkopieren",
            target: self,
            action: #selector(hinweiseGewaehlt(_:))
        )
        hinweise.state = einstellungen.hinweiseMitkopieren ? .on : .off
        hinweise.toolTip = "Ein paar Zeilen vor dem Text mit der Bitte, die Platzhalter stehen zu lassen."

        let nurLeiste = NSButton(
            checkboxWithTitle: "Nur in der Menüleiste, kein Dock-Symbol",
            target: self,
            action: #selector(darstellungGewaehlt(_:))
        )
        nurLeiste.state = einstellungen.nurMenueleiste ? .on : .off

        // Der Seed: aus ihm und dem Namen entsteht der Deckname.
        seedFeld.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        seedFeld.stringValue = woerterbuch.seed
        seedFeld.target = self
        seedFeld.action = #selector(seedUebernehmen)
        seedFeld.toolTip = "Einen Seed von einem anderen Rechner hier einfügen und ⏎ drücken."
        seedFeld.widthAnchor.constraint(equalToConstant: 300).isActive = true
        let kopieren = NSButton(title: "Kopieren", target: self, action: #selector(seedKopieren))
        kopieren.bezelStyle = .rounded
        let neu = NSButton(title: "Neu erzeugen", target: self, action: #selector(seedNeu))
        neu.bezelStyle = .rounded
        let seedZeile = NSStackView(views: [seedFeld, kopieren, neu])
        seedZeile.orientation = .horizontal
        seedZeile.spacing = 8
        let ableiten = NSButton(
            title: "Alle Decknamen aus dem Seed neu ableiten …",
            target: self,
            action: #selector(alleNeuAbleiten)
        )
        ableiten.bezelStyle = .rounded
        ableiten.toolTip = "Nach einem Seed-Wechsel: jeder Eintrag bekommt den Deckname, "
            + "der zum Seed passt. Die alten bleiben auflösbar."
        seedMeldung.font = .systemFont(ofSize: 11)
        seedMeldung.textColor = .secondaryLabelColor

        let stapel = NSStackView(views: [
            ueberschrift("Kurzbefehle"),
            beschriftet("Text schützen", schuetzenFeld),
            beschriftet("Zurückdrehen", rueckwegFeld),
            hinweisZeile("Sie gelten systemweit, auch wenn ein anderes Programm vorn ist. "
                + "Mindestens eine Zusatztaste ist Pflicht."),
            trenner(),
            ueberschrift("Popup"),
            beschriftet("Geht auf", position),
            trenner(),
            ueberschrift("Seed für die Decknamen"),
            beschriftet("Seed", seedZeile),
            beschriftet("", ableiten),
            beschriftet("", seedMeldung),
            hinweisZeile("Aus dem Seed und dem Namen entsteht der Deckname. Wer denselben Seed hat, "
                + "bekommt für denselben Namen denselben Deckname und kann deine Texte zurückdrehen, "
                + "sobald der Name in seinem Wörterbuch steht. Behandle den Seed wie ein Passwort."),
            trenner(),
            ueberschrift("Verhalten"),
            hinweise,
            nurLeiste,
            hinweisZeile("Das Wörterbuch liegt verschlüsselt in "
                + "~/Library/Application Support/de.risiq.textschleuse/. "
                + "Texte werden nie gespeichert."),
        ])
        stapel.orientation = .vertical
        stapel.spacing = 10
        stapel.alignment = .leading
        stapel.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 20, right: 22)
        stapel.translatesAutoresizingMaskIntoConstraints = false

        let allgemein = NSView()
        allgemein.addSubview(stapel)
        NSLayoutConstraint.activate([
            stapel.topAnchor.constraint(equalTo: allgemein.topAnchor),
            stapel.leadingAnchor.constraint(equalTo: allgemein.leadingAnchor),
            stapel.trailingAnchor.constraint(equalTo: allgemein.trailingAnchor),
            stapel.bottomAnchor.constraint(lessThanOrEqualTo: allgemein.bottomAnchor),
        ])

        let liste = FreilisteAnsicht(woerterbuch: woerterbuch)
        liste.beimSichern = { [weak self] geaendert in
            self?.woerterbuch = geaendert
            self?.beimWoerterbuch(geaendert)
        }
        freiliste = liste

        let reiter = NSTabView()
        reiter.translatesAutoresizingMaskIntoConstraints = false
        for (titel, ansicht) in [
            ("Allgemein", allgemein),
            ("Nie ersetzen", liste as NSView),
        ] {
            let seite = NSTabViewItem(identifier: titel)
            seite.label = titel
            seite.view = ansicht
            reiter.addTabViewItem(seite)
        }

        let inhalt = NSView()
        inhalt.addSubview(reiter)
        NSLayoutConstraint.activate([
            reiter.topAnchor.constraint(equalTo: inhalt.topAnchor, constant: 10),
            reiter.leadingAnchor.constraint(equalTo: inhalt.leadingAnchor, constant: 10),
            reiter.trailingAnchor.constraint(equalTo: inhalt.trailingAnchor, constant: -10),
            reiter.bottomAnchor.constraint(equalTo: inhalt.bottomAnchor, constant: -10),
        ])
        window?.contentView = inhalt
    }

    /// Für den Selbsttest.
    func freilisteFuerPruefung() -> FreilisteAnsicht? { freiliste }
    func seedFeldFuerPruefung() -> NSTextField { seedFeld }
    func setzeSeedFuerPruefung(_ seed: String) {
        seedFeld.stringValue = seed
        seedUebernehmen()
    }

    // MARK: Seed

    /// Nimmt das ins Wörterbuch, was im Feld steht — sobald ⏎ gedrückt oder
    /// das Feld verlassen wird.
    @objc private func seedUebernehmen() {
        let neu = seedFeld.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !neu.isEmpty else {
            seedFeld.stringValue = woerterbuch.seed
            melde("Ein leerer Seed geht nicht. Der bisherige bleibt.")
            return
        }
        guard neu != woerterbuch.seed else { return }
        woerterbuch.seed = neu
        seedFeld.stringValue = neu
        freiliste?.setze(woerterbuch: woerterbuch)
        beimWoerterbuch(woerterbuch)
        melde("Neuer Seed übernommen. Er gilt für alle Decknamen, die ab jetzt entstehen — "
            + "die bestehenden bleiben, bis du sie neu ableitest.")
    }

    @objc private func seedKopieren() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(woerterbuch.seed, forType: .string)
        melde("Seed in der Zwischenablage. Auf dem anderen Rechner hier einfügen und ⏎ drücken.")
    }

    @objc private func seedNeu() {
        seedFeld.stringValue = Decknamen.neuerSeed()
        seedUebernehmen()
    }

    @objc private func alleNeuAbleiten() {
        let anzahl = woerterbuch.eintraege.count
        guard anzahl > 0 else {
            melde("Das Wörterbuch ist leer, es gibt nichts abzuleiten.")
            return
        }
        let frage = NSAlert()
        frage.messageText = "Alle \(anzahl) Decknamen neu aus dem Seed ableiten?"
        frage.informativeText = "Jeder Eintrag bekommt den Deckname, der zu diesem Seed und seinem "
            + "Namen passt. Schon verschickte Texte gehen weiter auf, die alten Decknamen bleiben "
            + "als frühere erhalten. Selbst vergebene Decknamen ändern sich nicht."
        frage.addButton(withTitle: "Neu ableiten")
        frage.addButton(withTitle: "Abbrechen")
        guard frage.runModal() == .alertFirstButtonReturn else { return }

        let geaendert = woerterbuch.leiteAlleNeuAb()
        freiliste?.setze(woerterbuch: woerterbuch)
        beimWoerterbuch(woerterbuch)
        melde(geaendert == 0
            ? "Alle Decknamen passten schon zum Seed."
            : "\(geaendert) Decknamen neu abgeleitet, die alten bleiben auflösbar.")
    }

    private func melde(_ text: String) {
        seedMeldung.stringValue = text
    }

    private func ueberschrift(_ text: String) -> NSTextField {
        let feld = NSTextField(labelWithString: text)
        feld.font = .systemFont(ofSize: 13, weight: .semibold)
        return feld
    }

    private func hinweisZeile(_ text: String) -> NSTextField {
        let feld = NSTextField(wrappingLabelWithString: text)
        feld.font = .systemFont(ofSize: 11)
        feld.textColor = .secondaryLabelColor
        feld.preferredMaxLayoutWidth = 500
        return feld
    }

    private func trenner() -> NSBox {
        let linie = NSBox()
        linie.boxType = .separator
        return linie
    }

    private func beschriftet(_ titel: String, _ inhalt: NSView) -> NSView {
        let etikett = NSTextField(labelWithString: titel)
        etikett.font = .systemFont(ofSize: 12)
        etikett.alignment = .right
        etikett.translatesAutoresizingMaskIntoConstraints = false
        etikett.widthAnchor.constraint(equalToConstant: 130).isActive = true

        let zeile = NSStackView(views: [etikett, inhalt])
        zeile.orientation = .horizontal
        zeile.spacing = 10
        zeile.alignment = .centerY
        return zeile
    }

    // MARK: Aktionen

    @objc private func positionGewaehlt(_ absender: NSPopUpButton) {
        guard let roh = absender.selectedItem?.representedObject as? String,
              let wahl = PopupPosition(rawValue: roh)
        else { return }
        Einstellungen.gemeinsam.popupPosition = wahl
    }

    @objc private func hinweiseGewaehlt(_ absender: NSButton) {
        Einstellungen.gemeinsam.hinweiseMitkopieren = absender.state == .on
    }

    @objc private func darstellungGewaehlt(_ absender: NSButton) {
        let nurLeiste = absender.state == .on
        Einstellungen.gemeinsam.nurMenueleiste = nurLeiste
        beiDarstellung(nurLeiste)
    }
}

extension EinstellungenFenster: NSWindowDelegate {
    func windowWillClose(_ meldung: Notification) {
        EinstellungenFenster.offen = nil
    }
}
