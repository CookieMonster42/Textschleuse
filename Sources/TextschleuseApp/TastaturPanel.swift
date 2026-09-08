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

/// Kleine, selbstschließende Rückmeldung. Kommt, wenn im Text nichts zu
/// schützen war — damit du siehst, dass der Kurzbefehl angekommen ist.
enum KurzInfo {

    private static var offen: NSPanel?

    static func zeige(_ text: String, dauer: TimeInterval = 1.5) {
        offen?.orderOut(nil)

        let beschriftung = NSTextField(labelWithString: text)
        beschriftung.font = .systemFont(ofSize: 13, weight: .medium)
        beschriftung.alignment = .center
        beschriftung.lineBreakMode = .byWordWrapping
        beschriftung.preferredMaxLayoutWidth = 320

        let fussnote = NSTextField(labelWithString: "Schließt sich von selbst.")
        fussnote.font = .systemFont(ofSize: 11)
        fussnote.textColor = .secondaryLabelColor
        fussnote.alignment = .center

        let stapel = NSStackView(views: [beschriftung, fussnote])
        stapel.orientation = .vertical
        stapel.spacing = 6
        stapel.edgeInsets = NSEdgeInsets(top: 18, left: 22, bottom: 18, right: 22)
        stapel.frame = NSRect(x: 0, y: 0, width: 360, height: 90)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 90),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false

        let hintergrund = NSVisualEffectView()
        hintergrund.material = .hudWindow
        hintergrund.blendingMode = .behindWindow
        hintergrund.state = .active
        hintergrund.wantsLayer = true
        hintergrund.layer?.cornerRadius = 12
        hintergrund.addSubview(stapel)
        stapel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stapel.leadingAnchor.constraint(equalTo: hintergrund.leadingAnchor),
            stapel.trailingAnchor.constraint(equalTo: hintergrund.trailingAnchor),
            stapel.topAnchor.constraint(equalTo: hintergrund.topAnchor),
            stapel.bottomAnchor.constraint(equalTo: hintergrund.bottomAnchor),
        ])
        panel.contentView = hintergrund

        panel.setContentSize(stapel.fittingSize)
        let bildschirm = TastaturPanel.bildschirmUnterMaus.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: bildschirm.midX - panel.frame.width / 2,
            y: bildschirm.midY - panel.frame.height / 2
        ))
        panel.orderFrontRegardless()
        offen = panel

        DispatchQueue.main.asyncAfter(deadline: .now() + dauer) {
            guard offen === panel else { return }
            panel.orderOut(nil)
            offen = nil
        }
    }
}
