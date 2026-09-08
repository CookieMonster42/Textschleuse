import Foundation

/// Kleiner Ersatz für XCTest. Auf diesem Rechner sind nur die Command Line
/// Tools installiert, damit fehlt das XCTest-Modul. Der Prüfstand tut, was
/// hier gebraucht wird: Prüfungen benennen, Vergleiche zählen, am Ende einen
/// Rückgabewert ungleich null liefern, wenn etwas nicht stimmt.
enum Pruefstand {

    private static var laufendePruefung = ""
    private static var vergleiche = 0
    private static var fehler: [String] = []
    private static var pruefungenMitFehler = Set<String>()
    private static var pruefungen = 0

    static func pruefe(_ name: String, _ block: () -> Void) {
        laufendePruefung = name
        pruefungen += 1
        block()
    }

    static func wahr(_ bedingung: Bool, _ was: String) {
        vergleiche += 1
        guard !bedingung else { return }
        vermerke("\(was) — erwartet: ja, bekommen: nein")
    }

    static func falsch(_ bedingung: Bool, _ was: String) {
        wahr(!bedingung, was)
    }

    static func gleich<T: Equatable>(_ bekommen: T, _ erwartet: T, _ was: String) {
        vergleiche += 1
        guard bekommen != erwartet else { return }
        vermerke("\(was)\n      erwartet: \(erwartet)\n      bekommen: \(bekommen)")
    }

    static func enthaelt(_ heuhaufen: String, _ nadel: String, _ was: String) {
        vergleiche += 1
        guard !heuhaufen.contains(nadel) else { return }
        vermerke("\(was) — „\(nadel)\" fehlt im Ergebnis")
    }

    static func enthaeltNicht(_ heuhaufen: String, _ nadel: String, _ was: String) {
        vergleiche += 1
        guard heuhaufen.contains(nadel) else { return }
        vermerke("\(was) — „\(nadel)\" steht im Ergebnis, sollte aber nicht")
    }

    private static func vermerke(_ text: String) {
        fehler.append("  ✗ [\(laufendePruefung)] \(text)")
        pruefungenMitFehler.insert(laufendePruefung)
    }

    /// Gibt die Bilanz aus und beendet das Programm. Rückgabewert 1 bei
    /// Fehlern, damit ein Skript darauf reagieren kann.
    static func bilanzUndEnde() -> Never {
        print("")
        if fehler.isEmpty {
            print("✓ \(pruefungen) Prüfungen, \(vergleiche) Vergleiche, alles grün.")
            exit(0)
        }
        print("Fehlgeschlagen:")
        for zeile in fehler { print(zeile) }
        print("")
        print("✗ \(pruefungenMitFehler.count) von \(pruefungen) Prüfungen fehlgeschlagen "
            + "(\(fehler.count) von \(vergleiche) Vergleichen).")
        exit(1)
    }
}
