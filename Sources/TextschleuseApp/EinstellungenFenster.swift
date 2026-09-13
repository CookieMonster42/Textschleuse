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
    private let woerterbuch: Woerterbuch
    private let beimWoerterbuch: (Woerterbuch) -> Void
    private var freiliste: FreilisteAnsicht?

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
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
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
        liste.beimSichern = { [weak self] geaendert in self?.beimWoerterbuch(geaendert) }
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
