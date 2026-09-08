import AppKit

/// Grundgerüst für alle Fenster, die per Kurzbefehl aufgehen.
///
/// Das Panel nimmt die Tastatur an sich, solange es offen ist — anders ließe
/// sich Enter nicht abfangen. Beim Schließen geht der Fokus an die Anwendung
/// zurück, aus der du gekommen bist, damit du direkt einfügen kannst.
class TastaturPanel: NSPanel {

    private var vorherigeAnwendung: NSRunningApplication?

    init(groesse: NSSize) {
        vorherigeAnwendung = NSWorkspace.shared.frontmostApplication

        super.init(
            contentRect: NSRect(origin: .zero, size: groesse),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Größter erlaubter Zuschnitt: 70 Prozent der Bildschirmhöhe, damit das
    /// Fenster bei vierzig Fundstellen nicht über den Rand wächst.
    static func maximaleGroesse(auf bildschirm: NSScreen) -> NSSize {
        NSSize(
            width: min(980, bildschirm.visibleFrame.width * 0.8),
            height: bildschirm.visibleFrame.height * 0.7
        )
    }

    static var bildschirmUnterMaus: NSScreen {
        let maus = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(maus, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    func platziere(nach position: PopupPosition, auf bildschirm: NSScreen) {
        let rahmen = bildschirm.visibleFrame
        let meine = frame.size
        let ursprung: NSPoint

        switch position {
        case .mauszeiger:
            let maus = NSEvent.mouseLocation
            ursprung = NSPoint(
                x: min(max(rahmen.minX + 12, maus.x - meine.width / 2), rahmen.maxX - meine.width - 12),
                y: min(max(rahmen.minY + 12, maus.y - meine.height - 16), rahmen.maxY - meine.height - 12)
            )
        case .bildschirmmitte:
            ursprung = NSPoint(
                x: rahmen.midX - meine.width / 2,
                y: rahmen.midY - meine.height / 2
            )
        case .menueleiste:
            ursprung = NSPoint(
                x: rahmen.midX - meine.width / 2,
                y: rahmen.maxY - meine.height - 8
            )
        }
        setFrameOrigin(ursprung)
    }

    func zeige() {
        platziere(nach: Einstellungen.gemeinsam.popupPosition, auf: Self.bildschirmUnterMaus)
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    /// Schließt das Fenster und gibt den Fokus zurück.
    func schliesseUndGibFokusZurueck() {
        let ziel = vorherigeAnwendung
        orderOut(nil)
        // Erst nach dem Ausblenden aktivieren, sonst wechselt macOS wieder
        // zurück zu uns.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            ziel?.activate()
        }
    }
}
