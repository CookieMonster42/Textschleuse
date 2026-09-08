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
