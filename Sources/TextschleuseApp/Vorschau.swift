import AppKit
import TextschleuseCore

/// Zeichnet die Arbeitsflächen in PNG-Dateien, ohne dass jemand hinsieht.
///
///     Textschleuse.app/Contents/MacOS/Textschleuse --vorschau /tmp/bilder
///
/// Für den Blick auf das Layout, wenn man nicht am Bildschirm sitzt — etwa
/// beim Bauen auf einem anderen Rechner. Erzeugt je ein Bild vom Popup und
/// vom Hauptfenster, hell und dunkel.
enum Vorschau {

    static func laufen(nach ordner: String) -> Never {
        let ziel = URL(fileURLWithPath: ordner)
        try? FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        // Als richtiges Programm nach vorn: nur in einem aktiven Fenster
        // zeichnet AppKit Akzentfarbe und Auswahl so, wie man sie später sieht.
        NSApp.setActivationPolicy(.regular)
        NSApp.finishLaunching()

        var buch = Woerterbuch()
        _ = buch.anlegen(text: "Weidenbach", kategorie: .person)
        buch.schalte(.website, an: true)
        buch.schalte(.aktenzeichen, an: true)
        if CommandLine.arguments.contains("--alles-an") {
            for regel in Zusatzregel.alle { buch.schalte(regel, an: true) }
        }

        let probe = """
            Sehr geehrter Herr Nyström,

            anbei die Unterlagen zur Kontoverbindung DE89 3704 0044 0532 0130 00 von \
            Frau Weidenbach, Az. 12 O 345/21. Rückfragen an almut.weidenbach@example.org, \
            unter 0621 1234567 oder über www.weidenbach-partner.de/kontakt.

            Mit freundlichen Grüßen
            Thorben Nyström
            """
        let analyse = Schleuse.analysiere(probe, woerterbuch: buch)

        for dunkel in [false, true] {
            let name = dunkel ? "dunkel" : "hell"
            let erscheinung = NSAppearance(named: dunkel ? .darkAqua : .aqua)
            // Programmweit, nicht nur am Fenster: sonst zeichnen Knöpfe und
            // Etiketten beim Abbild noch hell.
            NSApp.appearance = erscheinung

            let popup = SchutzAnsicht(analyse: analyse)
            zeichne(popup, groesse: NSSize(width: 1000, height: 640), erscheinung: erscheinung,
                    nach: ziel.appendingPathComponent("popup-\(name).png"))

            // Die Antwort mit den Decknamen aus der Analyse, plus einem, den
            // niemand kennt.
            let deckname: (Kategorie) -> String = { kategorie in
                analyse.aktiveFunde.first { $0.kategorie == kategorie }?.platzhalter ?? "\(kategorie.praefix)_1"
            }
            let antwort = "Sehr geehrter Herr \(deckname(.person)), die Unterlagen von PERSON_9 zu "
                + "\(deckname(.aktenzeichen)) sind eingegangen. Rückfragen an \(deckname(.email))."
            let rueckweg = RueckwegAnsicht(
                ergebnis: Rueckweg.analysiere(antwort, woerterbuch: analyse.woerterbuch, unbekannte: analyse.unbekannte),
                woerterbuch: analyse.woerterbuch,
                unbekannte: analyse.unbekannte
            )
            zeichne(rueckweg, groesse: NSSize(width: 1000, height: 640), erscheinung: erscheinung,
                    nach: ziel.appendingPathComponent("rueckweg-\(name).png"))

            let blatt = Tastenkuerzel.baueInhalt()
            zeichne(blatt, groesse: blatt.fittingSize, erscheinung: erscheinung,
                    nach: ziel.appendingPathComponent("tastenkuerzel-\(name).png"))

            let sitzung = Sitzung()
            sitzung.beginne(analyse)
            let haupt = Hauptfenster(
                woerterbuch: { buch },
                sitzung: sitzung,
                beimSchuetzen: { _, _ in },
                beimZurueckdrehen: { _ in }
            )
            haupt.window?.appearance = erscheinung
            haupt.window?.setContentSize(NSSize(width: 1240, height: 780))
            if let fenster = haupt.window, let inhalt = fenster.contentView {
                fenster.makeKeyAndOrderFront(nil)
                fenster.layoutIfNeeded()
                drehe()
                schreibe(inhalt, nach: ziel.appendingPathComponent("hauptfenster-\(name).png"))
                fenster.orderOut(nil)
            }
            haupt.close()
        }
        print("Bilder liegen in \(ziel.path)")
        exit(0)
    }

    private static func zeichne(_ ansicht: NSView, groesse: NSSize, erscheinung: NSAppearance?, nach datei: URL) {
        let fenster = NSWindow(
            contentRect: NSRect(origin: .zero, size: groesse),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        fenster.appearance = erscheinung
        fenster.titlebarAppearsTransparent = true
        fenster.titleVisibility = .hidden
        fenster.contentView = ansicht
        fenster.makeKeyAndOrderFront(nil)
        fenster.layoutIfNeeded()
        drehe()
        schreibe(ansicht, nach: datei)
        fenster.orderOut(nil)
    }

    /// Lässt die Ereignisschleife kurz laufen. Ohne das haben Tabellen und
    /// Reiter noch nichts gezeichnet, wenn das Bild entsteht.
    private static func drehe() {
        NSApp.activate(ignoringOtherApps: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }

    private static func schreibe(_ ansicht: NSView, nach datei: URL) {
        ansicht.layoutSubtreeIfNeeded()
        guard let abbild = ansicht.bitmapImageRepForCachingDisplay(in: ansicht.bounds) else { return }
        ansicht.cacheDisplay(in: ansicht.bounds, to: abbild)

        // Die Ansicht zeichnet keinen Hintergrund, den malt das Fenster. Ohne
        // diese Fläche stünde im Dunkelmodus weiße Schrift auf Durchsichtig.
        let groesse = ansicht.bounds.size
        let bild = NSImage(size: groesse)
        bild.lockFocus()
        ansicht.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            NSRect(origin: .zero, size: groesse).fill()
        }
        abbild.draw(in: NSRect(origin: .zero, size: groesse))
        bild.unlockFocus()

        guard let tiff = bild.tiffRepresentation,
              let fertig = NSBitmapImageRep(data: tiff),
              let daten = fertig.representation(using: NSBitmapImageRep.FileType.png, properties: [:])
        else { return }
        try? daten.write(to: datei)
        print("   \(datei.lastPathComponent)  \(Int(groesse.width))×\(Int(groesse.height))")
    }
}
