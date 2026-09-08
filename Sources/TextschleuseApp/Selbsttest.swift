import AppKit
import Carbon.HIToolbox
import TextschleuseCore

/// Prüft die Teile, die kein Unit-Test erreicht: Keychain, Zwischenablage und
/// die Anmeldung eines globalen Kurzbefehls. Läuft ohne Oberfläche und beendet
/// sich selbst.
///
///     Textschleuse.app/Contents/MacOS/Textschleuse --selbsttest
///
/// Sinnvoll nach einem Rechnerwechsel oder wenn ein Kurzbefehl nicht mehr
/// anspringt.
enum Selbsttest {

    static func laufen() -> Never {
        var fehler = 0

        print("Textschleuse Selbsttest")
        print("Programm: \(Bundle.main.bundlePath)")
        print("Kennung:  \(Bundle.main.bundleIdentifier ?? "keine")")
        print("")

        fehler += pruefeKeychain()
        fehler += pruefeZwischenablage()
        fehler += pruefeKurzbefehl()
        fehler += pruefeDarstellung()

        print("")
        print(fehler == 0 ? "Alles in Ordnung." : "\(fehler) Punkt(e) fehlgeschlagen.")
        exit(fehler == 0 ? 0 : 1)
    }

    private static func pruefeKeychain() -> Int {
        let ordner = FileManager.default.temporaryDirectory
            .appendingPathComponent("textschleuse-selbsttest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: ordner) }

        let speicher = Speicher(ordner: ordner)
        var buch = Woerterbuch()
        _ = buch.anlegen(text: "Selbsttest Person", kategorie: .person)

        do {
            try speicher.sichern(buch)
            let geladen = try Speicher(ordner: ordner).laden()
            guard geladen.eintraege.first?.text == "Selbsttest Person" else {
                print("✗ Keychain: geladen, aber der Inhalt stimmt nicht")
                return 1
            }
            print("✓ Keychain: Schlüssel gelesen, verschlüsselt geschrieben und wieder gelesen")
            return 0
        } catch {
            print("✗ Keychain: \(error.localizedDescription)")
            print("  Ohne Zugriff läuft die App nicht. Ist das Bundle signiert? "
                + "Prüfen mit: codesign --verify --verbose \(Bundle.main.bundlePath)")
            return 1
        }
    }

    private static func pruefeZwischenablage() -> Int {
        let vorher = Zwischenablage.lies()
        defer { if let vorher { Zwischenablage.schreib(vorher) } }

        let probe = "Textschleuse Selbsttest \(UUID().uuidString)"
        Zwischenablage.schreib(probe)
        guard Zwischenablage.lies() == probe else {
            print("✗ Zwischenablage: geschrieben, aber anders zurückgelesen")
            return 1
        }
        print("✓ Zwischenablage: schreiben und lesen")
        return 0
    }

    /// Baut das Popup wirklich auf und misst, was darin steht. Ein leeres
    /// Textfeld sieht man auf dem Bildschirm sofort, aber erst, wenn man
    /// hinschaut — das hier fällt beim Bauen auf.
    private static func pruefeDarstellung() -> Int {
        let probe = """
            Sehr geehrter Herr Nyström, anbei die Unterlagen zur Kontoverbindung \
            DE89 3704 0044 0532 0130 00. Rückfragen an almut.weidenbach@example.org \
            oder 0621 1234567.
            """
        let analyse = Schleuse.analysiere(probe, woerterbuch: Woerterbuch())
        guard !analyse.funde.isEmpty else {
            print("✗ Darstellung: im Probetext nichts gefunden")
            return 1
        }

        var fehler = 0
        let popup = SchutzPopup(analyse: analyse) { _ in }
        popup.layoutIfNeeded()

        guard let inhalt = popup.contentView else {
            print("✗ Darstellung: das Fenster hat keinen Inhalt")
            return 1
        }

        // Kein Textfeld darf leer sein, und die Textfläche muss den größten
        // Teil der Höhe bekommen.
        let flaeche = rollflaecheSuchen(in: inhalt)
        let text = flaeche?.documentView as? NSTextView

        if let text, !text.string.isEmpty {
            print("✓ Darstellung: \(text.string.count) Zeichen im Textfeld, "
                + "\(analyse.funde.count) Fundstellen")
        } else {
            print("✗ Darstellung: das Textfeld ist leer")
            fehler += 1
        }

        if let flaeche {
            let anteil = flaeche.frame.height / inhalt.frame.height
            if anteil > 0.4 {
                print(String(format: "✓ Darstellung: Textfläche belegt %.0f %% der Fensterhöhe", anteil * 100))
            } else {
                print(String(format: "✗ Darstellung: Textfläche belegt nur %.0f %% der Fensterhöhe", anteil * 100))
                fehler += 1
            }
        }

        // Sitzt der Inhalt tatsächlich im Fenster oder ist er in eine Ecke
        // zusammengefallen?
        let fensterflaeche = popup.frame.width * popup.frame.height
        let inhaltsflaeche = inhalt.frame.width * inhalt.frame.height
        if inhaltsflaeche > fensterflaeche * 0.9 {
            print("✓ Darstellung: der Inhalt füllt das Fenster")
        } else {
            print("✗ Darstellung: der Inhalt füllt das Fenster nicht "
                + "(\(Int(inhalt.frame.width))×\(Int(inhalt.frame.height)) "
                + "in \(Int(popup.frame.width))×\(Int(popup.frame.height)))")
            fehler += 1
        }

        popup.orderOut(nil)
        return fehler
    }

    private static func rollflaecheSuchen(in ansicht: NSView) -> NSScrollView? {
        if let rolle = ansicht as? NSScrollView, rolle.documentView is NSTextView { return rolle }
        for unter in ansicht.subviews {
            if let treffer = rollflaecheSuchen(in: unter) { return treffer }
        }
        return nil
    }

    private static func pruefeKurzbefehl() -> Int {
        let einstellungen = Einstellungen.gemeinsam
        var fehler = 0

        for (name, kombination) in [
            ("Schützen", einstellungen.kurzbefehlSchuetzen),
            ("Zurückdrehen", einstellungen.kurzbefehlRueckweg),
        ] {
            if Kurzbefehle.gemeinsam.registriere(kombination, aktion: {}) != nil {
                print("✓ Kurzbefehl \(name): \(kombination.beschriftung) ist frei und angemeldet")
            } else {
                print("✗ Kurzbefehl \(name): \(kombination.beschriftung) ist von einem "
                    + "anderen Programm belegt")
                fehler += 1
            }
        }
        Kurzbefehle.gemeinsam.entferneAlle()
        return fehler
    }
}
