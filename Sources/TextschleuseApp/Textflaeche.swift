import AppKit

/// Eine Textansicht, die alle Tasten an das Fenster weiterreicht.
///
/// Sobald du mit der Maus in den Text klickst, wird die Ansicht erste
/// Antwortende und bekommt die Tastendrücke. Eine nicht editierbare
/// `NSTextView` verschluckt Ziffern und die Rücktaste dann kommentarlos, statt
/// sie weiterzureichen — die Tastenkürzel des Popups wären tot.
final class ChiptextAnsicht: NSTextView {

    /// Bekommt jeden Tastendruck zuerst. Liefert `true`, wenn er verarbeitet
    /// wurde; sonst geht er den gewohnten Weg.
    var tastenweiche: ((NSEvent) -> Bool)?

    override func keyDown(with ereignis: NSEvent) {
        if tastenweiche?(ereignis) == true { return }
        super.keyDown(with: ereignis)
    }
}

/// Baut eine `ChiptextAnsicht` in einer Rollfläche.
///
/// Warum das eine eigene Datei ist: `NSTextView()` allein zeichnet nichts.
/// Der Textcontainer hat keine Breite, das Größenverhalten ist ungesetzt, und
/// als `documentView` einer Rollfläche bleibt die Ansicht leer — ohne Fehler,
/// ohne Warnung. Hier steht der vollständige Zusammenbau an einer Stelle.
enum Textflaeche {

    struct Paar {
        let rolle: NSScrollView
        let text: ChiptextAnsicht
    }

    static func bauen() -> Paar {
        let speicher = NSTextStorage()
        let layout = NSLayoutManager()
        speicher.addLayoutManager(layout)

        let behaelter = NSTextContainer(
            size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        behaelter.widthTracksTextView = true
        layout.addTextContainer(behaelter)

        let text = ChiptextAnsicht(
            frame: NSRect(x: 0, y: 0, width: 480, height: 320),
            textContainer: behaelter
        )
        text.minSize = NSSize(width: 0, height: 0)
        text.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]

        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 10, height: 10)
        text.isAutomaticLinkDetectionEnabled = false
        text.isAutomaticQuoteSubstitutionEnabled = false
        // Chips tragen einen unsichtbaren Verweis, damit ein Klick sie
        // auswählen kann. Ohne diese Zeile malt AppKit sie blau und
        // unterstrichen.
        text.linkTextAttributes = [:]

        let rolle = NSScrollView()
        rolle.documentView = text
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
