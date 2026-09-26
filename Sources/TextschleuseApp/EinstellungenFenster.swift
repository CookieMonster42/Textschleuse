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
    /// Zeigt den Fingerabdruck, nie den ganzen Seed. Acht von 64 Stellen
    /// reichen, um zwei Seeds zu vergleichen, und verraten den Rest nicht.
    private let seedAnzeige = NSTextField(labelWithString: "")
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

        // Der Seed: aus ihm und dem Namen entsteht der Deckname. Zu sehen
        // ist nur der Fingerabdruck; kopiert wird der ganze.
        seedAnzeige.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        seedAnzeige.toolTip = "Die ersten acht Stellen des Seeds. Zum Vergleichen mit einem anderen Rechner."
        zeigeFingerabdruck()
        let kopieren = NSButton(title: "Seed kopieren", target: self, action: #selector(seedKopieren))
        kopieren.bezelStyle = .rounded
        kopieren.toolTip = "Legt den ganzen Seed in die Zwischenablage — für den anderen Rechner."
        let einfuegen = NSButton(title: "Aus Zwischenablage übernehmen …", target: self, action: #selector(seedEinfuegen))
        einfuegen.bezelStyle = .rounded
        einfuegen.toolTip = "Nimmt den Seed aus der Zwischenablage und leitet alle Decknamen neu ab."
        let neu = NSButton(title: "Neu erzeugen …", target: self, action: #selector(seedNeu))
        neu.bezelStyle = .rounded
        neu.toolTip = "Ein frischer Seed; alle Decknamen werden neu abgeleitet, die alten bleiben auflösbar."
        let seedZeile = NSStackView(views: [seedAnzeige, kopieren])
        seedZeile.orientation = .horizontal
        seedZeile.spacing = 8
        let wechselZeile = NSStackView(views: [einfuegen, neu])
        wechselZeile.orientation = .horizontal
        wechselZeile.spacing = 8
        let ableiten = NSButton(
            title: "Decknamen mit alter Nummer neu ableiten …",
            target: self,
            action: #selector(alleNeuAbleiten)
        )
        ableiten.bezelStyle = .rounded
        ableiten.toolTip = "Für Einträge aus der Zeit vor dem Seed, die noch PERSON_7 heißen. "
            + "Die alten Namen bleiben auflösbar."
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
            beschriftet("Fingerabdruck", seedZeile),
            beschriftet("Wechseln", wechselZeile),
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
    func seedFingerabdruckFuerPruefung() -> String { seedAnzeige.stringValue }
    /// Wie „Aus Zwischenablage übernehmen", nur ohne Zwischenablage und Rückfrage.
    @discardableResult
    func setzeSeedFuerPruefung(_ seed: String) -> Bool {
        wechsleSeed(auf: seed)
    }

    // MARK: Seed

    private func zeigeFingerabdruck() {
        seedAnzeige.stringValue = Decknamen.fingerabdruck(woerterbuch.seed) + " …"
    }

    /// Ein Seedwechsel ist ein Schritt: neuer Seed, alle Decknamen neu
    /// abgeleitet, die alten bleiben als frühere auflösbar. Selbst vergebene
    /// Decknamen bleiben unangetastet. Liefert false, wenn nichts zu tun war.
    @discardableResult
    private func wechsleSeed(auf eingabe: String) -> Bool {
        let neu = eingabe.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !neu.isEmpty else {
            melde("Ein leerer Seed geht nicht. Der bisherige bleibt.")
            return false
        }
        guard neu != woerterbuch.seed else {
            melde("Das ist schon der Seed dieses Wörterbuchs.")
            return false
        }
        woerterbuch.seed = neu
        let geaendert = woerterbuch.leiteAlleNeuAb()
        zeigeFingerabdruck()
        freiliste?.setze(woerterbuch: woerterbuch)
        beimWoerterbuch(woerterbuch)
        melde(geaendert == 0
            ? "Neuer Seed übernommen. Das Wörterbuch ist leer, es gab nichts abzuleiten."
            : "Neuer Seed übernommen, \(geaendert) Decknamen neu abgeleitet. Die alten bleiben auflösbar.")
        return true
    }

    /// Fragt vor dem Wechsel, weil sich danach jeder Deckname ändert.
    private func frageVorWechsel(_ titel: String, _ text: String) -> Bool {
        let frage = NSAlert()
        frage.messageText = titel
        let anzahl = woerterbuch.eintraege.count
        frage.informativeText = text + (anzahl > 0
            ? " Alle \(anzahl) Decknamen werden neu abgeleitet; schon verschickte Texte gehen weiter auf."
            : "")
        frage.addButton(withTitle: "Wechseln")
        frage.addButton(withTitle: "Abbrechen")
        return frage.runModal() == .alertFirstButtonReturn
    }

    @objc private func seedKopieren() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(woerterbuch.seed, forType: .string)
        melde("Der ganze Seed liegt in der Zwischenablage. Auf dem anderen Rechner: "
            + "„Aus Zwischenablage übernehmen\".")
    }

    @objc private func seedEinfuegen() {
        guard let inhalt = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !inhalt.isEmpty
        else {
            melde("In der Zwischenablage liegt kein Seed.")
            return
        }
        guard inhalt.count >= 16, inhalt.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
            melde("Das in der Zwischenablage sieht nicht nach einem Seed aus.")
            return
        }
        guard frageVorWechsel(
            "Seed \(Decknamen.fingerabdruck(inhalt)) … übernehmen?",
            "Danach vergibt dieses Wörterbuch dieselben Decknamen wie das, von dem der Seed stammt."
        ) else { return }
        wechsleSeed(auf: inhalt)
    }

    @objc private func seedNeu() {
        guard frageVorWechsel(
            "Einen neuen Seed erzeugen?",
            "Wer den bisherigen Seed kennt, kann neue Texte danach nicht mehr zuordnen."
        ) else { return }
        wechsleSeed(auf: Decknamen.neuerSeed())
    }

    @objc private func alleNeuAbleiten() {
        let anzahl = woerterbuch.eintraege.count
        guard anzahl > 0 else {
            melde("Das Wörterbuch ist leer, es gibt nichts abzuleiten.")
            return
        }
        let frage = NSAlert()
        frage.messageText = "Decknamen mit alter Nummer neu aus dem Seed ableiten?"
        frage.informativeText = "Einträge aus der Zeit vor dem Seed heißen noch PERSON_7. Sie bekommen "
            + "den Deckname, der zum Seed passt; die alten Namen bleiben als frühere auflösbar. "
            + "Selbst vergebene Decknamen ändern sich nicht."
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
