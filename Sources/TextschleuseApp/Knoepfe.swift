import AppKit

/// Baut die Knöpfe der Werkzeugleisten einheitlich: normale Größe, Symbol
/// vor der Beschriftung, Hilfetext mit der Taste.
///
/// Vorher waren es kleine Knöpfe mit der Taste in Klammern im Titel —
/// „Nur Text (⌘E)". Das war eng und schwer zu lesen. Jetzt trägt der Knopf
/// ein Symbol, und die Taste steht im Hilfetext; die Ziffern der Kategorien
/// stehen als Tastenkappe direkt am Knopf.
enum Knoepfe {

    static func knopf(
        _ titel: String,
        symbol: String?,
        ziel: AnyObject?,
        aktion: Selector,
        hilfe: String
    ) -> NSButton {
        let knopf = NSButton(title: titel, target: ziel, action: aktion)
        knopf.bezelStyle = .rounded
        knopf.controlSize = .regular
        knopf.font = .systemFont(ofSize: 13)
        knopf.toolTip = hilfe
        setze(symbol: symbol, auf: knopf)
        return knopf
    }

    /// Nur ein Symbol, kein Text — für Pfeile und Ähnliches.
    static func symbolknopf(
        _ symbol: String,
        beschreibung: String,
        ziel: AnyObject?,
        aktion: Selector,
        hilfe: String
    ) -> NSButton {
        let knopf = NSButton(title: "", target: ziel, action: aktion)
        knopf.bezelStyle = .rounded
        knopf.controlSize = .regular
        knopf.toolTip = hilfe
        knopf.image = NSImage(systemSymbolName: symbol, accessibilityDescription: beschreibung)
        knopf.imagePosition = .imageOnly
        knopf.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        knopf.widthAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        return knopf
    }

    static func setze(symbol: String?, auf knopf: NSButton) {
        guard let symbol, let bild = NSImage(systemSymbolName: symbol, accessibilityDescription: knopf.title) else {
            knopf.image = nil
            knopf.imagePosition = .noImage
            return
        }
        knopf.image = bild
        knopf.imagePosition = .imageLeading
        knopf.imageHugsTitle = true
        knopf.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
    }

    /// Das Symbol für eine Zifferntaste: „1.square" bis „0.square".
    static func tastenkappe(_ taste: String?) -> String? {
        guard let taste else { return nil }
        return "\(taste).square"
    }

    /// Ein Zeilenetikett links neben einer Werkzeugreihe.
    static func etikett(_ text: String) -> NSTextField {
        let feld = NSTextField(labelWithString: text)
        feld.font = .systemFont(ofSize: 12, weight: .medium)
        feld.textColor = .secondaryLabelColor
        feld.alignment = .right
        feld.setContentCompressionResistancePriority(.required, for: .horizontal)
        return feld
    }
}
