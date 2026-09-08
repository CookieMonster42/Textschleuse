import AppKit

/// Ein `NSTextView` in einer Rollfläche.
///
/// Warum das eine eigene Datei ist: `NSTextView()` allein zeichnet nichts.
/// Der Textcontainer hat keine Breite, das Größenverhalten ist ungesetzt, und
/// als `documentView` einer Rollfläche bleibt die Ansicht leer — ohne Fehler,
/// ohne Warnung. `scrollableTextView()` baut beides richtig zusammen.
enum Textflaeche {

    struct Paar {
        let rolle: NSScrollView
        let text: NSTextView
    }

    static func bauen(auswaehlbar: Bool = true) -> Paar {
        let rolle = NSTextView.scrollableTextView()
        guard let text = rolle.documentView as? NSTextView else {
            // Kann nicht eintreten; scrollableTextView liefert immer eine.
            return Paar(rolle: rolle, text: NSTextView())
        }

        text.isEditable = false
        text.isSelectable = auswaehlbar
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 10, height: 10)
        text.isAutomaticLinkDetectionEnabled = false
        text.isAutomaticQuoteSubstitutionEnabled = false
        // Chips tragen einen unsichtbaren Verweis, damit ein Klick sie
        // auswählen kann. Ohne diese Zeile malt AppKit sie blau und
        // unterstrichen.
        text.linkTextAttributes = [:]

        rolle.hasVerticalScroller = true
        rolle.hasHorizontalScroller = false
        rolle.autohidesScrollers = true
        rolle.drawsBackground = true
        rolle.backgroundColor = .textBackgroundColor
        rolle.borderType = .noBorder
        rolle.wantsLayer = true
        rolle.layer?.cornerRadius = 8
        rolle.translatesAutoresizingMaskIntoConstraints = false

        return Paar(rolle: rolle, text: text)
    }
}
