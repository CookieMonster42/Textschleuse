import AppKit
import TextschleuseCore

/// Sagt, was im Wörterbuch steht — in Zahlen, nicht in Namen.
///
///     Textschleuse.app/Contents/MacOS/Textschleuse --bestand
///
/// Gedacht für den Fall, dass unklar ist, ob Einträge verloren sind. Die
/// Ausgabe nennt Anzahl und Typ, nie einen Begriff und nie einen Decknamen.
/// Damit lässt sich der Bestand beurteilen, ohne ihn preiszugeben.
///
/// Schreibt nichts. Auch nicht den Sicherungsordner.
enum Bestandsbericht {

    static func laufen() -> Never {
        let speicher = Speicher()
        print("Textschleuse — Bestand")
        print("Ordner: \(speicher.ordner.path)")
        print("")

        if !speicher.hatDatei {
            print("Keine Datei. Es wurde noch nie gespeichert.")
            exit(0)
        }

        let groesse = (try? FileManager.default.attributesOfItem(atPath: speicher.datei.path)[.size])
            as? Int ?? -1
        print("Datei: \(groesse) Bytes")

        do {
            let buch = try speicher.laden()
            beschreibe("Aktuelle Datei", buch)
        } catch {
            print("✗ Lässt sich nicht lesen: \(error.localizedDescription)")
        }

        let sicherungen = speicher.sicherungen()
        print("")
        if sicherungen.isEmpty {
            print("Keine Sicherungen vorhanden.")
            print("Ab dieser Programmversion legt jedes Speichern eine an, in:")
            print("  \(speicher.sicherungsordner.path)")
            exit(0)
        }

        print("Sicherungen (\(sicherungen.count)), neueste zuerst:")
        for pfad in sicherungen {
            let anzahl = (try? speicher.lieseSicherung(pfad).eintraege.count).map(String.init)
                ?? "unlesbar"
            print("  \(pfad.lastPathComponent) — \(anzahl) Einträge")
        }
        print("")
        print("Zurückholen: „Wörterbuch › Aus Sicherung wiederherstellen …\" im Menü.")
        exit(0)
    }

    private static func beschreibe(_ titel: String, _ buch: Woerterbuch) {
        print("")
        print("\(titel): \(buch.eintraege.count) Einträge, "
            + "\(buch.eintraege.reduce(0) { $0 + $1.aliase.count }) Schreibweisen")
        for gruppe in Eintragsliste.gruppiert(buch.eintraege) {
            let automatisch = gruppe.eintraege.filter(\.automatischErkannt).count
            print("  \(gruppe.kategorie.anzeigepfad): \(gruppe.eintraege.count)"
                + (automatisch > 0 ? " (davon \(automatisch) automatisch erkannt)" : ""))
        }
        // Seit den Kennungen gibt es keine Nummern mehr. Was noch eine trägt,
        // stammt aus der Zeit davor und lässt sich in den Einstellungen neu
        // ableiten.
        let mitNummer = buch.eintraege.filter { $0.nummer > 0 }.count
        if mitNummer > 0 {
            print("  Einträge mit alter Nummer statt Kennung: \(mitNummer)")
        }
        print("  Seed-Fingerabdruck: \(Decknamen.fingerabdruck(buch.seed)) …")
    }
}
