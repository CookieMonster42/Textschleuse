import AppKit
import TextschleuseCore

/// Die Übersicht aller Tastenkürzel, als Blatt über dem Fenster.
///
/// Sie hängt an einem Knopf in jeder Arbeitsfläche, am Menü „Hilfe" (⌘/)
/// und erscheint beim Start, bis man das abschaltet. Die Knöpfe tragen ihre
/// Taste nicht mehr im Titel — hier steht alles an einer Stelle, geordnet
/// danach, wo man gerade ist.
enum Tastenkuerzel {

    struct Zeile {
        var tasten: [String]
        var wirkung: String
    }

    struct Abschnitt {
        var titel: String
        var zeilen: [Zeile]
    }

    /// Der Inhalt, mit den eingestellten Kurzbefehlen für die Zwischenablage.
    static func abschnitte(einstellungen: Einstellungen = .gemeinsam) -> [Abschnitt] {
        [
            Abschnitt(titel: "Überall", zeilen: [
                Zeile(tasten: [einstellungen.kurzbefehlSchuetzen.beschriftung], wirkung: "Zwischenablage schützen"),
                Zeile(tasten: [einstellungen.kurzbefehlRueckweg.beschriftung], wirkung: "Zwischenablage zurückdrehen"),
                Zeile(tasten: ["⌘0"], wirkung: "Fenster zeigen"),
                Zeile(tasten: ["⌘D"], wirkung: "Wörterbuch"),
                Zeile(tasten: ["⌘,"], wirkung: "Einstellungen"),
                Zeile(tasten: ["⌘/"], wirkung: "Diese Übersicht"),
            ]),
            Abschnitt(titel: "Fundstelle beim Schützen", zeilen: [
                Zeile(tasten: ["1", "…", "5"], wirkung: "Markierung schützen als Person, Firma, Ort, Nummer, Sonstiges"),
                Zeile(tasten: ["6", "…", "0"], wirkung: "als zugeschaltete Erkennung (Website, Anschrift …)"),
                Zeile(tasten: ["D"], wirkung: "gehört zu einem bekannten Eintrag"),
                Zeile(tasten: ["⌫"], wirkung: "verwerfen, bleibt Klartext (in der Liste)"),
                Zeile(tasten: ["↑", "↓"], wirkung: "vorige / nächste Fundstelle (in der Liste)"),
                Zeile(tasten: ["⌥↑", "⌥↓"], wirkung: "dasselbe, auch aus dem Text heraus"),
                Zeile(tasten: ["⏎"], wirkung: "im Deckname-Feld: übernehmen und weiter"),
                Zeile(tasten: ["⎋"], wirkung: "im Deckname-Feld: Eingabe verwerfen"),
            ]),
            Abschnitt(titel: "Text", zeilen: [
                Zeile(tasten: ["⌘F"], wirkung: "im Text suchen"),
                Zeile(tasten: ["⌘G", "⇧⌘G"], wirkung: "nächster / voriger Treffer"),
                Zeile(tasten: ["⌘E"], wirkung: "Decknamen im Text ein- und ausblenden"),
                Zeile(tasten: ["⌘N"], wirkung: "neuer Text aus der Zwischenablage"),
                Zeile(tasten: ["⌘Z", "⇧⌘Z"], wirkung: "widerrufen / wiederholen"),
                Zeile(tasten: ["⇥"], wirkung: "zwischen Text und Liste wechseln"),
                Zeile(tasten: ["⌘⌥D"], wirkung: "Wörterbuch neben dem Text (im Popup)"),
            ]),
            Abschnitt(titel: "Kopieren", zeilen: [
                Zeile(tasten: ["⌘⏎"], wirkung: "geschützten Text kopieren"),
                Zeile(tasten: ["⇧⌘⏎"], wirkung: "kopieren und alle offenen Vermutungen merken"),
                Zeile(tasten: ["⎋"], wirkung: "Popup schließen, nichts kopieren"),
            ]),
            Abschnitt(titel: "Zurückdrehen", zeilen: [
                Zeile(tasten: ["⌘⏎"], wirkung: "Ergebnis kopieren (⏎ in der Liste ebenso)"),
                Zeile(tasten: ["⌫"], wirkung: "Platzhalter ignorieren / wieder beachten (in der Liste)"),
                Zeile(tasten: ["↑", "↓"], wirkung: "voriger / nächster Platzhalter (in der Liste)"),
            ]),
        ]
    }

    private static var offenesBlatt: NSWindow?

    /// Zeigt die Übersicht als Blatt über dem Fenster. Ohne Fenster als
    /// eigenes, schwebendes Fenster.
    static func zeige(ueber fenster: NSWindow?) {
        guard offenesBlatt == nil else {
            offenesBlatt?.makeKeyAndOrderFront(nil)
            return
        }
        let blatt = baueBlatt()
        offenesBlatt = blatt
        if let fenster, fenster.isVisible, fenster.attachedSheet == nil {
            fenster.beginSheet(blatt) { _ in offenesBlatt = nil }
        } else {
            blatt.styleMask.insert(.titled)
            blatt.styleMask.insert(.closable)
            blatt.title = "Tastenkürzel"
            blatt.level = .floating
            blatt.center()
            blatt.isReleasedWhenClosed = false
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: blatt, queue: .main
            ) { _ in offenesBlatt = nil }
            blatt.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    static func schliesse() {
        guard let blatt = offenesBlatt else { return }
        if let eltern = blatt.sheetParent {
            eltern.endSheet(blatt)
        } else {
            blatt.close()
        }
        offenesBlatt = nil
    }

    /// Beim Start, solange das Häkchen gesetzt ist.
    static func zeigeBeimStart(ueber fenster: NSWindow?) {
        guard Einstellungen.gemeinsam.tastenkuerzelBeimStart else { return }
        zeige(ueber: fenster)
    }

    // MARK: Aufbau

    static func baueBlatt() -> NSWindow {
        let inhalt = baueInhalt()
        let fenster = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: inhalt.fittingSize.width, height: inhalt.fittingSize.height),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        fenster.contentView = inhalt
        return fenster
    }

    /// Der Inhalt des Blatts. Für sich, damit der Selbsttest ihn ohne Fenster
    /// aufbauen und durchsuchen kann.
    static func baueInhalt() -> NSView {
        let titel = NSTextField(labelWithString: "Tastenkürzel")
        titel.font = .systemFont(ofSize: 20, weight: .bold)
        let untertitel = NSTextField(wrappingLabelWithString:
            "Alles geht auch mit der Maus. Mit den Tasten geht es schneller: "
            + "markieren, Ziffer drücken, Deckname bestätigen, ⌘⏎.")
        untertitel.font = .systemFont(ofSize: 13)
        untertitel.textColor = .secondaryLabelColor
        untertitel.preferredMaxLayoutWidth = 700

        let alle = abschnitte()
        let links = NSStackView(views: alle.prefix(2).map(baueAbschnitt))
        let rechts = NSStackView(views: alle.dropFirst(2).map(baueAbschnitt))
        for spalte in [links, rechts] {
            spalte.orientation = .vertical
            spalte.alignment = .leading
            spalte.spacing = 18
        }
        let spalten = NSStackView(views: [links, rechts])
        spalten.orientation = .horizontal
        spalten.alignment = .top
        spalten.spacing = 36

        let haken = NSButton(checkboxWithTitle: "Beim Start zeigen", target: nil, action: nil)
        haken.state = Einstellungen.gemeinsam.tastenkuerzelBeimStart ? .on : .off
        haken.target = Haken.gemeinsam
        haken.action = #selector(Haken.geaendert(_:))

        let fertig = NSButton(title: "Verstanden", target: Haken.gemeinsam, action: #selector(Haken.schliessen))
        fertig.bezelStyle = .rounded
        fertig.keyEquivalent = "\r"
        let zu = NSButton(title: "", target: Haken.gemeinsam, action: #selector(Haken.schliessen))
        zu.keyEquivalent = "\u{1b}"
        zu.isHidden = true

        let fuss = NSStackView(views: [haken, NSView(), zu, fertig])
        fuss.orientation = .horizontal
        fuss.spacing = 12

        let stapel = NSStackView(views: [titel, untertitel, spalten, fuss])
        stapel.orientation = .vertical
        stapel.alignment = .leading
        stapel.spacing = 14
        stapel.setCustomSpacing(22, after: untertitel)
        stapel.setCustomSpacing(24, after: spalten)
        stapel.edgeInsets = NSEdgeInsets(top: 22, left: 26, bottom: 20, right: 26)
        stapel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            fuss.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -52),
            untertitel.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -52),
        ])
        return stapel
    }

    private static func baueAbschnitt(_ abschnitt: Abschnitt) -> NSView {
        let kopf = NSTextField(labelWithString: abschnitt.titel.uppercased())
        kopf.font = .systemFont(ofSize: 11, weight: .semibold)
        kopf.textColor = .secondaryLabelColor

        let raster = NSGridView(views: abschnitt.zeilen.map { zeile in
            [tasten(zeile.tasten), wirkung(zeile.wirkung)]
        })
        raster.rowSpacing = 6
        raster.columnSpacing = 12
        // Mittig statt an der Grundlinie: eine Tastenkappe hat keine.
        raster.rowAlignment = .none
        raster.yPlacement = .center
        raster.column(at: 0).xPlacement = .trailing
        raster.column(at: 0).width = 96

        let stapel = NSStackView(views: [kopf, raster])
        stapel.orientation = .vertical
        stapel.alignment = .leading
        stapel.spacing = 8
        return stapel
    }

    private static func tasten(_ tasten: [String]) -> NSView {
        let reihe = NSStackView(views: tasten.map(kappe))
        reihe.orientation = .horizontal
        reihe.spacing = 4
        reihe.alignment = .centerY
        return reihe
    }

    private static func wirkung(_ text: String) -> NSTextField {
        let feld = NSTextField(labelWithString: text)
        feld.font = .systemFont(ofSize: 13)
        feld.lineBreakMode = .byTruncatingTail
        return feld
    }

    /// Eine Tastenkappe: der Text auf grauem, rundem Grund.
    private static func kappe(_ text: String) -> NSView {
        if text == "…" {
            let punkte = NSTextField(labelWithString: "…")
            punkte.font = .systemFont(ofSize: 13)
            punkte.textColor = .secondaryLabelColor
            return punkte
        }
        let beschriftung = NSTextField(labelWithString: text)
        beschriftung.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        beschriftung.translatesAutoresizingMaskIntoConstraints = false

        let kappe = NSView()
        kappe.wantsLayer = true
        kappe.layer?.cornerRadius = 5
        kappe.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.09).cgColor
        kappe.layer?.borderWidth = 1
        kappe.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
        kappe.translatesAutoresizingMaskIntoConstraints = false
        kappe.addSubview(beschriftung)
        NSLayoutConstraint.activate([
            beschriftung.leadingAnchor.constraint(equalTo: kappe.leadingAnchor, constant: 7),
            beschriftung.trailingAnchor.constraint(equalTo: kappe.trailingAnchor, constant: -7),
            beschriftung.topAnchor.constraint(equalTo: kappe.topAnchor, constant: 2),
            beschriftung.bottomAnchor.constraint(equalTo: kappe.bottomAnchor, constant: -2),
            kappe.widthAnchor.constraint(greaterThanOrEqualToConstant: 26),
        ])
        return kappe
    }

    /// Ziel für Haken und Knopf. Ein Enum hat keinen `target`, deshalb ein
    /// winziges Objekt.
    private final class Haken: NSObject {
        static let gemeinsam = Haken()

        @objc func geaendert(_ absender: NSButton) {
            Einstellungen.gemeinsam.tastenkuerzelBeimStart = absender.state == .on
        }

        @objc func schliessen() {
            Tastenkuerzel.schliesse()
        }
    }
}
