import AppKit
import TextschleuseCore

/// Die Arbeitsfläche zum Schützen: links der Text mit den Fundstellen als
/// Chips, rechts die Liste mit ihrem Stand, unten die Werkzeuge für die
/// ausgewählte Fundstelle.
///
/// Steht als eigene Ansicht da und nicht im Fenster, weil zwei Fenster sie
/// zeigen: das Popup, das der Kurzbefehl aufmacht, und das Hauptfenster für
/// alle, die nicht über die Tastatur arbeiten wollen.
final class SchutzAnsicht: NSView, NSUserInterfaceValidations {

    /// Läuft, wenn übernommen wird. `merken` heißt: die noch offenen
    /// Vermutungen wandern ins Wörterbuch.
    var beiUebernahme: ((Analyse, Bool) -> Void)?
    /// Läuft bei Abbruch. Das Popup schließt sich daraufhin; im Hauptfenster
    /// wird der Text nur verworfen.
    var beiAbbruch: (() -> Void)?

    /// Läuft nach jeder Änderung. Die Sitzung schreibt damit mit, ohne dass
    /// man erst kopieren müsste — so sieht das Hauptfenster, was im Popup
    /// gerade passiert ist.
    var beiAenderung: ((Analyse) -> Void)?

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

    /// Aus heißt: Originaltext mit Chips, also `Meier → PERSON_1` inline.
    /// An heißt: nur der nackte Originaltext, wenn die Chips im Weg sind.
    private var ohneChips = false
    private var vorschauKnopf = NSButton()
    /// Sammelt Tastenanschläge, damit nicht bei jedem Buchstaben der ganze
    /// Text neu durchsucht wird.
    private var nachdenkpause: Timer?

    /// Der Widerruf arbeitet auf der ganzen Analyse, nicht auf dem Textfeld.
    ///
    /// Der eingebaute Widerruf einer `NSTextView` kann hier nicht greifen:
    /// jede Neuprüfung ersetzt den kompletten Textspeicher, danach zeigt sein
    /// Verlauf auf Text, den es nicht mehr gibt. Ein Stand ist deshalb immer
    /// alles zusammen — Text, Fundstellen und Wörterbuch.
    private let verlauf = UndoManager()

    /// Das kleine Feld, das bei einer Markierung neben der Stelle aufgeht.
    private var markierungsfeld: MarkierungsPopover?

    /// Das Wörterbuch als Klappe rechts. Im Popup zu, im Hauptfenster von
    /// außen aufgeklappt und dort auch nicht zuklappbar.
    private var woerterbuchKlappe: WoerterbuchAnsicht?
    private var klappeKnopf = NSButton()
    private var tastenKnopf = NSButton()
    private var klappeOffen = false
    /// Läuft, wenn in der Klappe etwas geändert wurde.
    var beiWoerterbuchAenderung: ((Woerterbuch) -> Void)?
    private var mitte = NSStackView()

    /// Der Fußbereich: drei beschriftete Reihen unter dem Text. „Schützen
    /// als" mit den Kategorien, „Fundstelle" mit Original und Deckname, „Text"
    /// mit den Werkzeugen und dem Kopieren. Die Reihen brechen um, statt das
    /// Fenster breit zu zwingen — mit zugeschalteten Erkennungen sind es bis
    /// zu zehn Kategorien.
    private let kategorienLeiste = Fliessleiste()
    private let werkzeugLeiste = Fliessleiste()
    /// Die Kategorien, für die gerade Knöpfe stehen. Ändert sich, sobald in
    /// den Einstellungen eine Erkennung zu- oder abgeschaltet wird.
    private var gebauteKategorien: [Kategorie] = []
    private var kategorieKnoepfe: [NSButton] = []
    private var verwerfenKnopf = NSButton()
    private var gruppeKnopf = NSButton()
    private var zurueckKnopf = NSButton()
    private var vorKnopf = NSButton()
    private var kopierenKnopf = NSButton()
    /// Die Knöpfe, die eine ausgewählte Fundstelle brauchen. Kopieren, Leeren
    /// oder Suchen gehören nicht dazu — die gehen immer.
    private var stellenKnoepfe: [NSButton] {
        kategorieKnoepfe + [verwerfenKnopf, gruppeKnopf, zurueckKnopf, vorKnopf]
    }
    private let originalFeld = NSTextField()
    private let originalEtikett = NSTextField(labelWithString: "Original")
    private let decknameFeld = NSTextField()
    private let decknameEtikett = NSTextField(labelWithString: "Deckname")
    private let merkenHaken = NSButton(checkboxWithTitle: "dauerhaft merken", target: nil, action: nil)
    /// Die Rückmeldung unter den Feldern. Steht immer da, auch leer — sonst
    /// springt der Fußbereich bei jeder Meldung um eine Zeile.
    private let meldung = NSTextField(labelWithString: "")
    /// Die Tasten, die an keinem Knopf stehen.
    private let fusszeile = NSTextField(wrappingLabelWithString: "")

    init(analyse: Analyse) {
        self.analyse = analyse
        super.init(frame: NSRect(x: 0, y: 0, width: 960, height: 600))
        baueOberflaeche()
        aktualisiere()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }

    /// Setzt den Fokus dorthin, wo man ihn braucht: in die Liste, solange es
    /// Fundstellen gibt, sonst in den Text.
    ///
    /// In der Liste navigieren Pfeil hoch und runter ohne Zusatztaste, und die
    /// Ziffern wirken auf die ausgewählte Stelle. Im Text bewegen dieselben
    /// Pfeiltasten die Schreibmarke — beides zugleich geht nicht.
    @discardableResult
    func fokussiereFundstellen() -> Bool {
        if liste.fokussiere() { return true }
        window?.makeFirstResponder(textAnsicht)
        return false
    }

    /// Wirft den bisherigen Text weg und fängt mit einem neuen an.
    func setze(analyse neue: Analyse) {
        // Ein neuer Text fängt einen neuen Verlauf an; alles davor gehört zu
        // einem Text, den es nicht mehr gibt.
        verlauf.removeAllActions()
        analyse = neue
        auswahl = 0

        textAnsicht.setSelectedRange(NSRange(location: 0, length: 0))
        zeigeMeldung(nil)
        aktualisiere()
        textAnsicht.scroll(NSPoint(x: 0, y: 0))
        fokussiereFundstellen()
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

        // Der Text ist direkt bearbeitbar. Was dasteht, ist der Originaltext;
        // die Fundstellen sind nur eingefärbt, es wird nichts dazwischen
        // geschoben. Nur so kann man tippen, ohne die Zuordnung zu zerreißen.
        textAnsicht.isEditable = true
        textAnsicht.isRichText = false
        // Aus: sonst kämen sich zwei Verläufe in die Quere.
        textAnsicht.allowsUndo = false
        textAnsicht.font = .systemFont(ofSize: 13)

        klappeKnopf = NSButton(title: "Wörterbuch ▸", target: self, action: #selector(klappeUmschalten))
        klappeKnopf.bezelStyle = .rounded
        klappeKnopf.controlSize = .small
        klappeKnopf.toolTip = "Das Wörterbuch neben dem Text aufklappen (⌘⌥D)"

        mitte = NSStackView(views: [rollflaeche, liste])
        mitte.orientation = .horizontal
        mitte.spacing = 12
        mitte.distribution = .fill
        mitte.translatesAutoresizingMaskIntoConstraints = false

        tastenKnopf = Knoepfe.knopf(
            "Tastenkürzel", symbol: "keyboard",
            ziel: self, aktion: #selector(zeigeTastenkuerzel),
            hilfe: "Alle Tasten auf einen Blick (⌘/)"
        )
        tastenKnopf.controlSize = .small
        tastenKnopf.font = .systemFont(ofSize: 11)

        let kopfzeileMitKlappe = NSStackView(views: [kopfzeile, NSView(), tastenKnopf, klappeKnopf])
        kopfzeileMitKlappe.orientation = .horizontal
        kopfzeileMitKlappe.spacing = 8
        kopfzeileMitKlappe.translatesAutoresizingMaskIntoConstraints = false

        let fuss = baueFussbereich()

        let stapel = NSStackView(views: [kopfzeileMitKlappe, regelzeile, suche, mitte, fuss])
        stapel.orientation = .vertical
        stapel.spacing = 10
        stapel.alignment = .leading
        stapel.edgeInsets = NSEdgeInsets(top: 28, left: 18, bottom: 14, right: 18)

        stapel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stapel)
        NSLayoutConstraint.activate([
            stapel.topAnchor.constraint(equalTo: topAnchor),
            stapel.leadingAnchor.constraint(equalTo: leadingAnchor),
            stapel.trailingAnchor.constraint(equalTo: trailingAnchor),
            stapel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        for zeile in [kopfzeile, regelzeile] {
            zeile.setContentHuggingPriority(.required, for: .vertical)
        }
        kopfzeileMitKlappe.setContentHuggingPriority(.required, for: .vertical)
        for teil in [fuss, suche] {
            teil.setContentHuggingPriority(.required, for: .vertical)
            teil.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        mitte.setContentHuggingPriority(.defaultLow, for: .vertical)
        mitte.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        NSLayoutConstraint.activate([
            mitte.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -36),
            mitte.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
            // 300 statt 260: eine Zufallskennung ist achtzehn Stellen lang.
            liste.widthAnchor.constraint(equalToConstant: 300),
            kopfzeileMitKlappe.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -36),
            suche.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -36),
            fuss.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -36),
        ])
    }

    /// Der Bereich unter dem Text.
    ///
    /// Drei beschriftete Reihen, damit man auf einen Blick sieht, was wozu
    /// gehört: was mit der Stelle geschehen soll, wie sie heißt, und was mit
    /// dem Text als Ganzem passiert. Vorher standen fünfzehn kleine Knöpfe in
    /// zwei Reihen, die Taste in Klammern im Titel — zu klein, zu eng.
    private func baueFussbereich() -> NSView {
        let trennlinie = NSBox()
        trennlinie.boxType = .separator
        trennlinie.translatesAutoresizingMaskIntoConstraints = false

        // Reihe „Schützen als": die Kategorien, dahinter Verwerfen und Zuordnen.
        verwerfenKnopf = Knoepfe.knopf(
            "Verwerfen", symbol: "delete.left",
            ziel: self, aktion: #selector(verwerfenGeklickt),
            hilfe: "Diese Stelle bleibt im Klartext stehen. ⌫ in der Liste macht dasselbe."
        )
        gruppeKnopf = Knoepfe.knopf(
            "Gehört zu …", symbol: "d.square",
            ziel: self, aktion: #selector(gruppeGeklickt),
            hilfe: "Als weitere Schreibweise an einen bekannten Eintrag hängen. "
                + "D bei markiertem Text, sonst ⌘D."
        )
        kategorienLeiste.translatesAutoresizingMaskIntoConstraints = false
        baueKategorieKnoepfe()

        // Reihe „Fundstelle": Original, Deckname, merken.
        for etikett in [originalEtikett, decknameEtikett] {
            etikett.font = .systemFont(ofSize: 13)
            etikett.textColor = .secondaryLabelColor
        }
        originalFeld.font = .systemFont(ofSize: 13)
        originalFeld.placeholderString = "so steht es im Text"
        originalFeld.target = self
        originalFeld.action = #selector(originalUebernehmen)
        originalFeld.delegate = self
        originalFeld.toolTip = "Korrigiert, was an dieser Stelle im Text steht. ⏎ übernimmt, ⎋ verwirft."

        decknameFeld.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        decknameFeld.placeholderString = "PERSON_3F9A1C7B2E4D6A0B5C"
        decknameFeld.target = self
        decknameFeld.action = #selector(decknameUebernehmen)
        decknameFeld.delegate = self
        decknameFeld.toolTip = "Großbuchstaben, Ziffern, Unterstrich. ⏎ übernimmt, ⎋ verwirft."

        merkenHaken.state = .on
        merkenHaken.font = .systemFont(ofSize: 13)
        merkenHaken.target = self
        merkenHaken.action = #selector(merkenGeaendert)
        merkenHaken.toolTip = "Aus heißt: der Deckname gilt nur für diesen Text."

        // Der Rest der Zeile bleibt leer, statt dass die Felder bis zum Rand
        // wachsen: ein 800 Punkte breites Feld für „Nyström" sieht verloren
        // aus. Wird es eng, geben die Felder bis auf ein Mindestmaß nach.
        let rest = NSView()
        rest.setContentHuggingPriority(NSLayoutConstraint.Priority(100), for: .horizontal)
        let fundstelleZeile = NSStackView(views: [
            originalEtikett, originalFeld, decknameEtikett, decknameFeld, merkenHaken, rest,
        ])
        fundstelleZeile.orientation = .horizontal
        fundstelleZeile.spacing = 8
        fundstelleZeile.setCustomSpacing(18, after: originalFeld)
        fundstelleZeile.setCustomSpacing(18, after: decknameFeld)
        fundstelleZeile.alignment = .firstBaseline
        fundstelleZeile.translatesAutoresizingMaskIntoConstraints = false
        for (feld, wunsch, mindestens) in [(originalFeld, 240, 130), (decknameFeld, 270, 150)] {
            feld.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let gern = feld.widthAnchor.constraint(equalToConstant: CGFloat(wunsch))
            // Unter 500: sonst schlägt der Wunsch die Fenstergröße, und das
            // Fenster ließe sich nicht mehr schmaler ziehen als diese Zeile.
            gern.priority = NSLayoutConstraint.Priority(400)
            NSLayoutConstraint.activate([
                gern,
                feld.widthAnchor.constraint(greaterThanOrEqualToConstant: CGFloat(mindestens)),
            ])
        }

        meldung.font = .systemFont(ofSize: 12)
        meldung.textColor = .secondaryLabelColor
        meldung.lineBreakMode = .byTruncatingTail
        meldung.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Reihe „Text": Fundstelle vor und zurück, die Werkzeuge, ganz rechts
        // das Kopieren als Abschluss.
        zurueckKnopf = Knoepfe.symbolknopf(
            "chevron.up", beschreibung: "Vorige Fundstelle",
            ziel: self, aktion: #selector(aktionVorigeFundstelle(_:)),
            hilfe: "Vorige Fundstelle (⌥↑)"
        )
        vorKnopf = Knoepfe.symbolknopf(
            "chevron.down", beschreibung: "Nächste Fundstelle",
            ziel: self, aktion: #selector(aktionNaechsteFundstelle(_:)),
            hilfe: "Nächste Fundstelle (⌥↓)"
        )
        let suchKnopf = Knoepfe.knopf(
            "Suchen", symbol: "magnifyingglass",
            ziel: self, aktion: #selector(aktionSuchen(_:)),
            hilfe: "Im Text suchen (⌘F)"
        )
        let widerrufKnopf = Knoepfe.knopf(
            "Widerrufen", symbol: "arrow.uturn.backward",
            ziel: self, aktion: #selector(undo(_:)),
            hilfe: "Letzte Änderung zurücknehmen (⌘Z)"
        )
        vorschauKnopf = Knoepfe.knopf(
            "Nur Text", symbol: "eye.slash",
            ziel: self, aktion: #selector(vorschauUmschalten),
            hilfe: "Blendet die Decknamen im Text aus (⌘E). Bearbeiten geht in beiden Fällen."
        )
        let leeren = Knoepfe.knopf(
            "Leeren", symbol: "trash",
            ziel: self, aktion: #selector(leeren),
            hilfe: "Wirft den Text weg. Das Wörterbuch bleibt."
        )
        let neu = Knoepfe.knopf(
            "Neuer Text", symbol: "doc.on.clipboard",
            ziel: self, aktion: #selector(neuEinlesen),
            hilfe: "Liest, was jetzt in der Zwischenablage liegt (⌘N). Der bisherige Text wird verworfen."
        )
        werkzeugLeiste.translatesAutoresizingMaskIntoConstraints = false
        werkzeugLeiste.setze([
            zurueckKnopf, vorKnopf, Gruppentrenner(),
            suchKnopf, widerrufKnopf, vorschauKnopf, Gruppentrenner(),
            leeren, neu,
        ])

        kopierenKnopf = Knoepfe.knopf(
            "Geschützten Text kopieren", symbol: "lock.fill",
            ziel: self, aktion: #selector(kopierenGeklickt),
            hilfe: "⌘⏎ — in die Zwischenablage, dann im KI-Tool einfügen. "
                + "⇧⌘⏎ merkt dabei alle offenen Vermutungen."
        )
        kopierenKnopf.keyEquivalent = "\r"
        kopierenKnopf.keyEquivalentModifierMask = [.command]
        // Der eine Knopf, um den es am Ende geht, in der Akzentfarbe. Ab
        // macOS 26 heißt das „primäre Tönung", davor ist es die Bezelfarbe.
        if #available(macOS 26.0, *) {
            kopierenKnopf.tintProminence = .primary
        } else {
            kopierenKnopf.bezelColor = .controlAccentColor
        }
        kopierenKnopf.setContentHuggingPriority(.required, for: .horizontal)
        kopierenKnopf.setContentCompressionResistancePriority(.required, for: .horizontal)

        let textZeile = NSStackView(views: [werkzeugLeiste, kopierenKnopf])
        textZeile.orientation = .horizontal
        textZeile.spacing = 16
        textZeile.alignment = .firstBaseline
        textZeile.translatesAutoresizingMaskIntoConstraints = false
        werkzeugLeiste.setContentHuggingPriority(.defaultLow, for: .horizontal)

        fusszeile.font = .systemFont(ofSize: 12)
        fusszeile.textColor = .tertiaryLabelColor
        fusszeile.preferredMaxLayoutWidth = 900
        fusszeile.stringValue = "⌘⏎ kopiert · ⇧⌘⏎ kopiert und merkt alle offenen Vermutungen · "
            + "⇥ wechselt zwischen Text und Liste · ⎋ bricht ab"

        // Drei Reihen mit Etikett links. Die Etiketten sind gleich breit,
        // damit die Reihen an einer Kante beginnen.
        let etikettBreite: CGFloat = 84
        var reihen: [NSStackView] = []
        for (name, inhalt) in [
            ("Schützen als", kategorienLeiste as NSView),
            ("Fundstelle", fundstelleZeile),
            ("", meldung),
            ("Text", textZeile),
        ] {
            let etikett = Knoepfe.etikett(name)
            let reihe = NSStackView(views: [etikett, inhalt])
            reihe.orientation = .horizontal
            reihe.spacing = 12
            reihe.alignment = .firstBaseline
            reihe.translatesAutoresizingMaskIntoConstraints = false
            etikett.widthAnchor.constraint(equalToConstant: etikettBreite).isActive = true
            inhalt.setContentHuggingPriority(.defaultLow, for: .horizontal)
            reihen.append(reihe)
        }

        let fuss = NSStackView(views: [trennlinie] + reihen + [fusszeile])
        fuss.orientation = .vertical
        fuss.spacing = 10
        fuss.alignment = .leading
        fuss.setCustomSpacing(14, after: trennlinie)
        // Die Meldung rückt an die Felder heran, zu denen sie gehört.
        fuss.setCustomSpacing(4, after: reihen[1])
        fuss.setCustomSpacing(14, after: reihen[3])
        fuss.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate(
            [trennlinie.widthAnchor.constraint(equalTo: fuss.widthAnchor),
             fusszeile.widthAnchor.constraint(equalTo: fuss.widthAnchor)]
            + reihen.map { $0.widthAnchor.constraint(equalTo: fuss.widthAnchor) }
        )
        return fuss
    }

    /// Die Kategorien, die im Fenster zur Wahl stehen — mit den zugeschalteten
    /// Erkennungen aus dem Wörterbuch.
    private var kategorienZurWahl: [Kategorie] {
        Kategorie.zurWahl(mit: analyse.woerterbuch)
    }

    /// „1–5", „1–7" oder „1–9 und 0": die Tasten, die gerade Kategorien tragen.
    private var tastenhinweis: String {
        let anzahl = kategorienZurWahl.count
        if anzahl >= 10 { return "1–9 und 0" }
        return "1–\(anzahl)"
    }

    private func kategorie(fuerTaste zeichen: String) -> Kategorie? {
        guard let platz = Kategorie.platz(fuerTaste: zeichen) else { return nil }
        let reihe = kategorienZurWahl
        return reihe.indices.contains(platz) ? reihe[platz] : nil
    }

    /// Die Knöpfe für „Schützen als": die fünf festen Kategorien, dahinter
    /// die zugeschalteten Erkennungen. Wird neu gebaut, sobald sich die Reihe
    /// ändert — etwa weil in den Einstellungen „Anschrift" dazukam.
    private func baueKategorieKnoepfe() {
        let reihe = kategorienZurWahl
        guard reihe != gebauteKategorien || kategorieKnoepfe.isEmpty else { return }
        gebauteKategorien = reihe

        kategorieKnoepfe = reihe.enumerated().map { platz, kategorie in
            let taste = Kategorie.taste(fuerPlatz: platz)
            let knopf = Knoepfe.knopf(
                kategorie.anzeigename,
                symbol: Knoepfe.tastenkappe(taste),
                ziel: self,
                aktion: #selector(kategorieGeklickt(_:)),
                hilfe: taste.map { "Text markieren, dann \($0) drücken — oder ⌘\($0) ohne Markierung" }
                    ?? "Als \(kategorie.anzeigename) schützen"
            )
            knopf.tag = platz
            return knopf
        }
        kategorienLeiste.setze(kategorieKnoepfe + [Gruppentrenner(), verwerfenKnopf, gruppeKnopf])
    }

    // MARK: Darstellung

    private func aktualisiere(originalMarke: Int? = nil) {
        reihenfolge = analyse.funde
            .filter { !$0.verworfen }
            .sorted { $0.bereich.location < $1.bereich.location }
            .map(\.id)
        auswahl = reihenfolge.isEmpty ? 0 : min(auswahl, reihenfolge.count - 1)

        let gewaehlt = reihenfolge.indices.contains(auswahl) ? reihenfolge[auswahl] : nil
        let aufbau = ohneChips
            ? Chiptext.aufbauenOriginal(analyse: analyse, ausgewaehlt: gewaehlt)
            : Chiptext.aufbauen(analyse: analyse, ausgewaehlt: gewaehlt)
        bereiche = aufbau.bereiche
        textAnsicht.textStorage?.setAttributedString(aufbau.text)
        if let originalMarke {
            let stelle = Chiptext.anzeigePosition(fuer: originalMarke, in: aufbau.text)
            textAnsicht.setSelectedRange(NSRange(location: stelle, length: 0))
        }

        beschrifteKopf()

        liste.zeige(
            analyse.funde.sorted { $0.bereich.location < $1.bereich.location }.map(listenzeile),
            ausgewaehlt: gewaehlt,
            leertext: analyse.original.isEmpty
                ? "Kein Text zum Prüfen."
                : "Nichts erkannt.\n\nMarkiere links im Text, was geschützt werden soll, "
                    + "und drücke \(tastenhinweis)."
        )

        if let gewaehlt, let bereich = bereiche[gewaehlt] {
            springeZu(bereich)
        }
        // Der Text ist neu aufgebaut, die alten Trefferbereiche zeigen ins Leere.
        suche.aktualisiere()
        baueKategorieKnoepfe()
        aktualisiereWerkzeuge()
        klappeNachziehen()
        beiAenderung?(analyse)
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
                + "werden soll, und drücke \(tastenhinweis). Mit ⌘⏎ kopierst du ihn so, wie er ist."
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
        for knopf in stellenKnoepfe {
            knopf.isEnabled = fund != nil || hatFreieMarkierung
        }
        // Zuordnen geht auch ohne Vorschlag: du weißt oft besser als die
        // Heuristik, wer gemeint ist. Aber nur, wenn das Wörterbuch schon
        // jemanden kennt.
        gruppeKnopf.isEnabled = (fund != nil || hatFreieMarkierung)
            && !analyse.woerterbuch.eintraege.isEmpty
        if let vorschlag = fund?.gruppenVorschlag,
           let eintrag = analyse.woerterbuch.eintrag(mitId: vorschlag) {
            gruppeKnopf.toolTip = "Vorschlag: \(eintrag.text) (\(eintrag.platzhalter))"
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

    private var textHatFokus: Bool {
        guard let erster = window?.firstResponder else { return false }
        return erster === textAnsicht
    }

    /// Rote Meldung für Fehler. Erfolgsmeldungen setzt `meldeNachtrag`.
    private func zeigeMeldung(_ text: String?) {
        meldung.textColor = .systemRed
        meldung.stringValue = text ?? ""
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
            case "d" where zusatz.contains(.option):
                klappeUmschalten()
                return true
            case "g":
                if zusatz.contains(.shift) { suche.vorheriger() } else { suche.naechster() }
                return true
            case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
                if let kategorie = kategorie(fuerTaste: ereignis.charactersIgnoringModifiers ?? "") {
                    setzeKategorie(kategorie)
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
        case 53 where markierungsfeld != nil:  // ⎋ schließt erst das Feld
            schliesseMarkierungsfeld()
            textAnsicht.setSelectedRange(NSRange(location: 0, length: 0))
            aktualisiere()
            return true
        case 53:  // Escape
            abbrechen()
            return true
        // Pfeiltasten: mit ⌥ von überall, ohne ⌥ nur dann, wenn die
        // Schreibmarke nicht im Text sitzt — dort gehören sie ihr.
        case 126 where zusatz.contains(.option) || !textHatFokus:
            waehle(auswahl - 1)
            return true
        case 125 where zusatz.contains(.option) || !textHatFokus:
            waehle(auswahl + 1)
            return true
        case 51 where !textHatFokus:  // Rücktaste in der Liste
            verwerfeAktuellen()
            return true
        case 48:  // Tabulator: zwischen Text und Liste wechseln
            if textHatFokus { fokussiereFundstellen() } else { window?.makeFirstResponder(textAnsicht) }
            return true
        default:
            break
        }

        // Solange nichts markiert ist, gehören Ziffern dem Text: er ist
        // bearbeitbar, da soll eine 1 eine 1 schreiben.
        //
        // Ist etwas markiert, ist die Sache eindeutig: eine Ziffer würde die
        // Markierung überschreiben, und das will niemand. Also heißt sie hier
        // Kategorie.
        // Zwei Fälle, in denen eine Ziffer die Kategorie meint: es ist etwas
        // im Text markiert, oder der Fokus liegt in der Liste. Im dritten Fall
        // — Schreibmarke im Text, nichts markiert — tippt sie eine Ziffer.
        guard textAnsicht.selectedRange().length > 0 || !textHatFokus,
              let zeichen = ereignis.charactersIgnoringModifiers?.lowercased()
        else { return false }

        if let kategorie = kategorie(fuerTaste: zeichen) {
            setzeKategorie(kategorie)
            return true
        }
        if zeichen == "d" {
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

        // Die Stelle auch im Text markieren. Dann wirken 1 bis 5 direkt auf
        // sie, ohne dass man sie nochmal mit der Maus einfangen muss.
        if let bereich = bereiche[kennung], NSMaxRange(bereich) <= textAnsicht.string.count {
            textAnsicht.setSelectedRange(bereich)
        }
    }

    // MARK: Aktionen

    @objc private func kategorieGeklickt(_ absender: NSButton) {
        let reihe = kategorienZurWahl
        guard reihe.indices.contains(absender.tag) else { return }
        setzeKategorie(reihe[absender.tag])
    }

    @objc private func kopierenGeklickt() { uebernehmen(merken: false) }

    /// Das Häkchen ändert, was die Kategorietasten tun. Die Kopfzeile sagt
    /// das bei einer Markierung — also muss sie beim Umschalten nachziehen.
    @objc private func merkenGeaendert() {
        if hatFreieMarkierung {
            kopfzeile.stringValue = merkenHaken.state == .on
                ? "Markierung: Taste \(tastenhinweis) legt sie als neuen Eintrag an"
                : "Markierung: Taste \(tastenhinweis) schützt sie nur in diesem Text"
        } else {
            beschrifteKopf()
        }
    }

    @objc private func verwerfenGeklickt() { verwerfeAktuellen() }

    @objc private func gruppeGeklickt() { gruppeUebernehmen() }

    /// Eine Kategorie zuweisen. Liegt eine eigene Markierung im Text, gilt sie;
    /// sonst die ausgewählte Fundstelle.
    private func setzeKategorie(_ kategorie: Kategorie) {
        zeigeMeldung(nil)
        merkeStand("Kategorie zuweisen")

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
            schliesseMarkierungsfeld()
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

        merkeStand("Zuordnen")
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
        merkeStand("Verwerfen")
        let betroffen = Schleuse.verwerfe(fundId: fund.id, in: &analyse)
        aktualisiere()

        meldung.textColor = .secondaryLabelColor
        meldung.stringValue = betroffen > 1
            ? "„\(fund.text)" + "\" bleibt an allen \(betroffen) Stellen im Klartext. ⌘Z nimmt das zurück."
            : "„\(fund.text)" + "\" bleibt im Klartext. ⌘Z nimmt das zurück."
        meldung.isHidden = false
    }

    // MARK: Wörterbuch-Klappe

    /// Klappt das Wörterbuch rechts neben der Fundstellenliste auf.
    ///
    /// Im Popup ist es zu: dort geht es um einen Text, nicht um Pflege. Im
    /// Hauptfenster hängt es dauerhaft dran und der Knopf verschwindet.
    /// Nimmt ein von außen geändertes Wörterbuch an — etwa aus der Spalte im
    /// Hauptfenster — und prüft den Text damit neu.
    func uebernimmWoerterbuch(_ geaendert: Woerterbuch) {
        guard geaendert.eintraege.count != analyse.woerterbuch.eintraege.count
            || geaendert.alleDecknamen != analyse.woerterbuch.alleDecknamen
        else { return }
        let marke = originalMarke()
        analyse = Schleuse.analysiere(analyse.original, woerterbuch: geaendert)
        auswahl = 0
        aktualisiere(originalMarke: marke)
    }

    /// Im Hauptfenster steht das Wörterbuch als eigene Spalte; dann braucht es
    /// den Knopf zum Aufklappen nicht.
    func verbergeKlappenknopf() {
        klappeKnopf.isHidden = true
    }

    @objc func klappeUmschalten() {
        klappeOffen ? klappeZu() : klappeAuf()
    }

    @objc func zeigeTastenkuerzel() {
        Tastenkuerzel.zeige(ueber: window)
    }

    func klappeAuf(dauerhaft: Bool = false) {
        guard !klappeOffen else { return }
        let ansicht = WoerterbuchAnsicht(
            woerterbuch: analyse.woerterbuch,
            schmal: true,
            beimSichern: { [weak self] geaendert in
                guard let self else { return }
                // Der Text muss nachziehen: was gerade gemerkt wurde, gilt ab
                // jetzt auch in dieser Analyse.
                self.analyse.woerterbuch = geaendert
                self.beiWoerterbuchAenderung?(geaendert)
                self.aktualisiere()
            },
            beimExportieren: { _, _ in }
        )
        ansicht.translatesAutoresizingMaskIntoConstraints = false
        mitte.addArrangedSubview(ansicht)
        NSLayoutConstraint.activate([
            ansicht.widthAnchor.constraint(equalToConstant: 520),
        ])
        woerterbuchKlappe = ansicht
        klappeOffen = true
        klappeKnopf.title = "Wörterbuch ◂"
        klappeKnopf.isHidden = dauerhaft
    }

    func klappeZu() {
        woerterbuchKlappe?.removeFromSuperview()
        woerterbuchKlappe = nil
        klappeOffen = false
        klappeKnopf.title = "Wörterbuch ▸"
    }

    /// Nach jeder Änderung im Text den Stand in der Klappe nachziehen.
    private func klappeNachziehen() {
        woerterbuchKlappe?.setze(woerterbuch: analyse.woerterbuch)
        woerterbuchKlappe?.setze(imText: Set(analyse.aktiveFunde.compactMap(\.eintragId)))
    }

    // MARK: Feld bei der Markierung

    /// Klappt das kleine Feld neben der markierten Stelle auf.
    ///
    /// Es zeigt dasselbe wie die Knopfleiste unten, nur dort, wo man gerade
    /// hinschaut. Wer die Ziffern schon kennt, braucht es nicht — deshalb
    /// stehen sie mit auf den Knöpfen.
    private func zeigeMarkierungsfeld() {
        guard let bereich = freieMarkierung, markierungsfeld == nil else { return }
        let text = (analyse.original as NSString).substring(with: bereich)

        let feld = MarkierungsPopover(
            begriff: text,
            kategorien: kategorienZurWahl,
            kannZuordnen: !analyse.woerterbuch.eintraege.isEmpty
        ) { [weak self] entscheidung in
            guard let self else { return }
            self.markierungsfeld = nil
            switch entscheidung {
            case .kategorie(let kategorie, let merken):
                self.merkenHaken.state = merken ? .on : .off
                self.setzeKategorie(kategorie)
            case .gehoertZu:
                self.gruppeUebernehmen()
            }
        }
        markierungsfeld = feld
        feld.zeige(neben: textAnsicht, bei: rahmenDerMarkierung())
    }

    private func schliesseMarkierungsfeld() {
        markierungsfeld?.schliesse()
        markierungsfeld = nil
    }

    /// Der Rahmen der Markierung in den Koordinaten der Textansicht. Daran
    /// hängt das Feld, damit es die Stelle nicht verdeckt.
    private func rahmenDerMarkierung() -> NSRect {
        let anzeige = textAnsicht.selectedRange()
        guard let layout = textAnsicht.layoutManager,
              let behaelter = textAnsicht.textContainer,
              anzeige.length > 0
        else { return NSRect(x: 0, y: 0, width: 1, height: 1) }

        layout.ensureLayout(for: behaelter)
        let zeichen = layout.glyphRange(forCharacterRange: anzeige, actualCharacterRange: nil)
        var rahmen = layout.boundingRect(forGlyphRange: zeichen, in: behaelter)
        rahmen.origin.x += textAnsicht.textContainerOrigin.x
        rahmen.origin.y += textAnsicht.textContainerOrigin.y
        return rahmen
    }

    // MARK: Tasten und Menü

    /// Ohne das nimmt die Ansicht den Tastaturfokus gar nicht erst an — und
    /// `makeFirstResponder` scheitert stumm. Genau daran lagen die
    /// Tastenkürzel, sobald man vorher einen Knopf oder die Liste angeklickt
    /// hatte.
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with ereignis: NSEvent) {
        if verarbeite(ereignis) { return }
        super.keyDown(with: ereignis)
    }

    /// Die Befehle aus dem Menü „Aktionen". Sie laufen über die Antwortkette
    /// und greifen deshalb auch dann, wenn der Fokus woanders im Fenster
    /// steht. Jeder Knopf im Fenster ruft dieselbe Methode.
    @objc func aktionKategorie(_ absender: NSMenuItem) {
        let reihe = kategorienZurWahl
        guard reihe.indices.contains(absender.tag) else { return }
        setzeKategorie(reihe[absender.tag])
    }

    @objc func aktionKopieren(_ absender: Any?) { uebernehmen(merken: false) }
    @objc func aktionKopierenUndMerken(_ absender: Any?) { uebernehmen(merken: true) }
    @objc func aktionVerwerfen(_ absender: Any?) { verwerfeAktuellen() }
    @objc func aktionZuordnen(_ absender: Any?) { gruppeUebernehmen() }
    @objc func aktionLeeren(_ absender: Any?) { leeren() }
    @objc func aktionNeuerText(_ absender: Any?) { neuEinlesen() }
    @objc func aktionDecknamenUmschalten(_ absender: Any?) { vorschauUmschalten() }
    @objc func aktionSuchen(_ absender: Any?) { suche.oeffne() }
    @objc func aktionWoerterbuchKlappe(_ absender: Any?) { klappeUmschalten() }
    @objc func aktionNaechsteFundstelle(_ absender: Any?) { waehle(auswahl + 1) }
    @objc func aktionVorigeFundstelle(_ absender: Any?) { waehle(auswahl - 1) }

    func validateUserInterfaceItem(_ eintrag: NSValidatedUserInterfaceItem) -> Bool {
        switch eintrag.action {
        case #selector(aktionKategorie(_:)):
            return aktuellerFund != nil || hatFreieMarkierung
        case #selector(aktionVerwerfen(_:)):
            return aktuellerFund != nil
        case #selector(aktionZuordnen(_:)):
            return (aktuellerFund != nil || hatFreieMarkierung) && !analyse.woerterbuch.eintraege.isEmpty
        case #selector(aktionNaechsteFundstelle(_:)), #selector(aktionVorigeFundstelle(_:)):
            return !reihenfolge.isEmpty
        case #selector(undo(_:)):
            return verlauf.canUndo
        case #selector(redo(_:)):
            return verlauf.canRedo
        default:
            return true
        }
    }

    // MARK: Widerrufen

    override var undoManager: UndoManager? { verlauf }

    func undoManager(for ansicht: NSTextView) -> UndoManager? { verlauf }

    @objc func undo(_ absender: Any?) { verlauf.undo() }

    @objc func redo(_ absender: Any?) { verlauf.redo() }

    /// Legt den jetzigen Stand auf den Stapel. Vor jeder Änderung aufrufen.
    private func merkeStand(_ name: String) {
        let stand = analyse
        let marke = originalMarke()
        verlauf.registerUndo(withTarget: self) { ziel in
            // Beim Widerrufen denselben Weg rückwärts eintragen, damit ⇧⌘Z
            // wieder vorwärts geht.
            ziel.merkeStand(name)
            ziel.setzeStand(stand, marke: marke)
        }
        verlauf.setActionName(name)
    }

    private func setzeStand(_ stand: Analyse, marke: Int) {
        analyse = stand
        auswahl = 0
        zeigeMeldung(nil)
        aktualisiere(originalMarke: marke)
    }

    // MARK: Für den Selbsttest

    func leerenFuerPruefung() { leeren() }
    func setzeTextFuerPruefung(_ text: String) {
        textAnsicht.string = text
        pruefeJetzt()
    }
    func istInVorschauFuerPruefung() -> Bool { ohneChips }
    func widerrufeFuerPruefung() { verlauf.undo() }
    func wiederholeFuerPruefung() { verlauf.redo() }
    func kannWiderrufenFuerPruefung() -> Bool { verlauf.canUndo }
    func darfAendernFuerPruefung(_ bereich: NSRange) -> Bool {
        textView(textAnsicht, shouldChangeTextIn: bereich, replacementString: "x")
    }
    func vorschauUmschaltenFuerPruefung() { vorschauUmschalten() }
    func waehleFundFuerPruefung(_ kennung: UUID) { waehleFund(kennung) }
    func ausgewaehlterFundFuerPruefung() -> UUID? { aktuellerFund?.id }
    /// Löst die Neuprüfung sofort aus, ohne die Tipppause abzuwarten.
    func pruefeJetztFuerPruefung() { pruefeJetzt() }
    func ausgewaehlterBegriffFuerPruefung() -> String? { aktuellerFund?.text }
    func decknameUebernehmenFuerPruefung() { decknameUebernehmen() }
    @discardableResult
    func fokussiereTextFuerPruefung() -> Bool {
        window?.makeFirstResponder(textAnsicht) ?? false
    }
    func pfeilFuerPruefung(runter: Bool) -> Bool {
        guard let ereignis = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: runter ? 125 : 126
        ) else { return false }
        return verarbeite(ereignis)
    }
    func markiereFuerPruefung(_ bereich: NSRange) { textAnsicht.setSelectedRange(bereich) }
    func tasteFuerPruefung(_ zeichen: String) -> Bool {
        guard let ereignis = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: zeichen,
            charactersIgnoringModifiers: zeichen,
            isARepeat: false,
            keyCode: 0
        ) else { return false }
        return verarbeite(ereignis)
    }

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

    /// Schaltet die Chips ab und an. Bearbeitbar bleibt der Text in beiden
    /// Fällen — die Chips sind nur Anzeige.
    @objc private func vorschauUmschalten() {
        let marke = originalMarke()
        ohneChips.toggle()
        vorschauKnopf.title = ohneChips ? "Mit Decknamen" : "Nur Text"
        Knoepfe.setze(symbol: ohneChips ? "eye" : "eye.slash", auf: vorschauKnopf)
        aktualisiere(originalMarke: marke)
        window?.makeFirstResponder(textAnsicht)
    }

    /// Die Schreibmarke, gezählt in Originalzeichen. Nur so übersteht sie ein
    /// Neuzeichnen, bei dem die Decknamen ihre Länge ändern.
    private func originalMarke() -> Int {
        Chiptext.originalPosition(
            fuer: textAnsicht.selectedRange().location,
            in: textAnsicht.attributedString()
        )
    }

    /// Wirft den Text weg und lässt dich gleich tippen. Ohne das müsste man
    /// erst irgendwas anderes kopieren, um den alten Text loszuwerden.
    @objc private func leeren() {
        merkeStand("Leeren")
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
        // Aus der Anzeige den Originaltext herausschälen: Pfeile und
        // Decknamen sind Zutat der App und fallen weg.
        let getippt = Chiptext.originaltext(aus: textAnsicht.attributedString())
        guard getippt != analyse.original else { return }

        let marke = originalMarke()
        // Ein Stand je Tipppause, nicht je Anschlag. ⌘Z nimmt damit den
        // ganzen zusammenhängenden Schwung zurück.
        merkeStand("Tippen")

        // Merken, wo man war: nach einer Korrektur mitten im Text will man
        // dort weitermachen und nicht wieder bei der ersten Fundstelle.
        let vorherigerBegriff = aktuellerFund?.text
        let vorherigeStelle = aktuellerFund?.bereich.location

        analyse = Schleuse.analysiereErneut(getippt, wie: analyse)
        aktualisiere(originalMarke: marke)
        stelleAuswahlWiederHer(begriff: vorherigerBegriff, nahe: vorherigeStelle)
    }

    /// Sucht nach einer Neuanalyse dieselbe Fundstelle wieder: erst über den
    /// Wortlaut, sonst die nächstgelegene.
    private func stelleAuswahlWiederHer(begriff: String?, nahe stelle: Int?) {
        guard !reihenfolge.isEmpty else {
            auswahl = 0
            return
        }
        let funde = reihenfolge.compactMap { kennung in
            analyse.funde.first { $0.id == kennung }
        }
        if let begriff,
           let index = funde.firstIndex(where: {
               $0.text.compare(begriff, options: .caseInsensitive) == .orderedSame
           }) {
            auswahl = index
        } else if let stelle {
            let naechste = funde.enumerated().min {
                abs($0.element.bereich.location - stelle) < abs($1.element.bereich.location - stelle)
            }
            auswahl = naechste?.offset ?? 0
        } else {
            auswahl = 0
        }
        aktualisiere()
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

        merkeStand("Neuer Text")
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

        merkeStand("Original ändern")
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
            merkeStand("Deckname ändern")
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

    /// Springt zur nächsten offenen Stelle *hinter* der aktuellen.
    ///
    /// Vorher war es immer die erste offene im Text. Wer sich von oben nach
    /// unten durcharbeitet, landete damit nach jeder Entscheidung wieder am
    /// Anfang und musste sich erneut nach unten hangeln.
    ///
    /// Ist hinter der aktuellen nichts mehr offen, geht es einmal um: dann
    /// steht vorne noch etwas, das übersprungen wurde.
    private func weiterZurNaechstenLuecke() {
        let bisher = aktuellerFund?.bereich.location ?? -1
        aktualisiere()

        let offene = analyse.funde
            .filter(\.brauchtPruefung)
            .sorted { $0.bereich.location < $1.bereich.location }
        guard !offene.isEmpty else { return }

        let naechste = offene.first { $0.bereich.location > bisher } ?? offene[0]
        guard let index = reihenfolge.firstIndex(of: naechste.id) else { return }
        auswahl = index
        aktualisiere()
        if let bereich = bereiche[naechste.id], NSMaxRange(bereich) <= textAnsicht.string.count {
            textAnsicht.setSelectedRange(bereich)
        }
        // Zurück in die Liste: dort greifen die Pfeiltasten und die Ziffern
        // sofort weiter.
        fokussiereFundstellen()
    }

    func uebernehmen(merken: Bool) {
        beiUebernahme?(analyse, merken)
    }

    /// Im Hauptfenster bleibt der Text nach dem Kopieren stehen — dann muss
    /// eine Zeile sagen, dass es geklappt hat.
    func meldeKopiert() {
        meldung.textColor = .secondaryLabelColor
        meldung.stringValue = "In die Zwischenablage gelegt. Jetzt im KI-Tool einfügen."
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

    /// Der Text lässt sich bearbeiten wie jeder andere: tippen, alles
    /// markieren, löschen. Nur mitten in einen Decknamen tippen geht nicht.
    /// Ein Löschen, das einen Chip anschneidet, nimmt gleich den ganzen Chip
    /// mit — sonst käme der Name beim nächsten Prüfen einfach wieder.
    func textView(
        _ ansicht: NSTextView,
        shouldChangeTextIn bereich: NSRange,
        replacementString ersatz: String?
    ) -> Bool {
        guard ansicht === textAnsicht else { return true }
        switch Chiptext.pruefeAenderung(
            bereich: bereich, ersatz: ersatz, in: textAnsicht.attributedString(), chips: bereiche
        ) {
        case .erlaubt:
            return true
        case .verboten:
            zeigeMeldung("Den Decknamen im Text kann man nicht ändern. Das Feld unten schon.")
            return false
        case .ausweiten(let ganz):
            Chiptext.loescheSpaeter(ganz, in: textAnsicht)
            return false
        }
    }

    /// Jede Eingabe im Text löst nach einer kurzen Pause eine neue Prüfung aus.
    func textDidChange(_ meldung: Notification) {
        guard meldung.object as AnyObject? === textAnsicht else { return }
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
                ? "Markierung: Taste \(tastenhinweis) legt sie als neuen Eintrag an"
                : "Markierung: Taste \(tastenhinweis) schützt sie nur in diesem Text"
            zeigeMarkierungsfeld()
        } else {
            beschrifteKopf()
            schliesseMarkierungsfeld()
        }
    }
}
