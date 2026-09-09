import AppKit
import TextschleuseCore

/// Das eigene Fenster fürs Wörterbuch. Hält nur den Rahmen; der Inhalt steckt
/// in `WoerterbuchAnsicht`, damit Hauptfenster und Popup ihn auch zeigen
/// können.
final class WoerterbuchFenster: NSWindowController {

    private static var offen: WoerterbuchFenster?

    static func zeige(
        woerterbuch: Woerterbuch,
        beimSichern: @escaping (Woerterbuch) -> Void,
        beimExportieren: @escaping (URL, Woerterbuch) throws -> Void
    ) {
        offen?.close()
        let fenster = WoerterbuchFenster(
            woerterbuch: woerterbuch,
            beimSichern: beimSichern,
            beimExportieren: beimExportieren
        )
        offen = fenster
        fenster.showWindow(nil)
        fenster.window?.makeKeyAndOrderFront(nil)
    }

    init(
        woerterbuch: Woerterbuch,
        beimSichern: @escaping (Woerterbuch) -> Void,
        beimExportieren: @escaping (URL, Woerterbuch) throws -> Void
    ) {
        let ansicht = WoerterbuchAnsicht(
            woerterbuch: woerterbuch,
            beimSichern: beimSichern,
            beimExportieren: beimExportieren
        )
        let fenster = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        fenster.title = "Mein Wörterbuch"
        fenster.center()
        super.init(window: fenster)

        ansicht.translatesAutoresizingMaskIntoConstraints = false
        let behaelter = NSView()
        behaelter.addSubview(ansicht)
        NSLayoutConstraint.activate([
            ansicht.topAnchor.constraint(equalTo: behaelter.topAnchor),
            ansicht.leadingAnchor.constraint(equalTo: behaelter.leadingAnchor),
            ansicht.trailingAnchor.constraint(equalTo: behaelter.trailingAnchor),
            ansicht.bottomAnchor.constraint(equalTo: behaelter.bottomAnchor),
        ])
        fenster.contentView = behaelter
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }
}
