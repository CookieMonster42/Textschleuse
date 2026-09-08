import AppKit

/// Zugriff auf die Zwischenablage. Gelesen und geschrieben wird ausschließlich
/// reiner Text: für einen KI-Prompt bringt Rich Text nichts, und beim Ersetzen
/// innerhalb von RTF gehen Auszeichnungen kaputt.
enum Zwischenablage {

    static func lies() -> String? {
        let inhalt = NSPasteboard.general.string(forType: .string)
        guard let inhalt, !inhalt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return inhalt
    }

    static func schreib(_ text: String) {
        let ablage = NSPasteboard.general
        ablage.clearContents()
        ablage.setString(text, forType: .string)
    }
}
