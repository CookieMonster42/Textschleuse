import AppKit

/// Reiht Knöpfe von links nach rechts auf und bricht in eine neue Zeile um,
/// sobald die Breite nicht reicht.
///
/// Ein `NSStackView` kann das nicht: er staucht oder blendet aus. Mit den
/// zugeschalteten Erkennungen wird die Kategorienreihe aber bis zu zehn
/// Knöpfe lang, und im Hauptfenster hat sie neben der Wörterbuchspalte nur
/// gut 600 Punkte Platz.
final class Fliessleiste: NSView {

    var abstand: CGFloat = 6
    var zeilenabstand: CGFloat = 8

    private(set) var teile: [NSView] = []
    private var gemesseneHoehe: CGFloat = 0

    override var isFlipped: Bool { true }

    func setze(_ neue: [NSView]) {
        for alt in teile { alt.removeFromSuperview() }
        teile = neue
        for teil in neue {
            teil.translatesAutoresizingMaskIntoConstraints = true
            addSubview(teil)
        }
        gemesseneHoehe = ordne(breite: bounds.width, setzen: false)
        needsLayout = true
        invalidateIntrinsicContentSize()
    }

    /// Rechnet die Höhe für eine bekannte Breite vor. Für Stellen, die die
    /// Größe vor dem ersten Layout brauchen — ein Popover misst seinen Inhalt
    /// beim Öffnen und wächst danach nicht mehr mit.
    func bemesse(breite: CGFloat) {
        gemesseneHoehe = ordne(breite: breite, setzen: false)
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: gemesseneHoehe)
    }

    /// Die Grundlinie des ersten Knopfs, damit ein Etikett daneben auf einer
    /// Höhe mit dessen Beschriftung steht.
    override var firstBaselineOffsetFromTop: CGFloat {
        guard let erster = teile.first(where: { !$0.isHidden }) else { return 0 }
        let groesse = erster.fittingSize
        let zeilenhoehe = teile.filter { !$0.isHidden }.map { $0.fittingSize.height }.max() ?? groesse.height
        return (zeilenhoehe - groesse.height) / 2 + erster.firstBaselineOffsetFromTop
    }

    override func layout() {
        super.layout()
        let hoehe = ordne(breite: bounds.width, setzen: true)
        if hoehe != gemesseneHoehe {
            gemesseneHoehe = hoehe
            invalidateIntrinsicContentSize()
        }
    }

    /// Verteilt die Teile auf Zeilen und liefert die Gesamthöhe. Bei
    /// unbekannter Breite (noch kein Layout) kommt alles in eine Zeile.
    ///
    /// Ein `Gruppentrenner` hält zusammen, was hinter ihm steht: passt die
    /// Gruppe nicht mehr in die Zeile, wandert sie geschlossen in die nächste
    /// — sonst stünde „Gehört zu …" allein unter sieben Kategorien. Am
    /// Zeilenanfang oder -ende fällt der Trenner weg.
    @discardableResult
    private func ordne(breite: CGFloat, setzen: Bool) -> CGFloat {
        let sichtbar = teile.filter { !$0.isHidden }
        guard !sichtbar.isEmpty else { return 0 }

        var zeilen: [[NSView]] = [[]]
        var x: CGFloat = 0
        var index = 0
        while index < sichtbar.count {
            let teil = sichtbar[index]
            let w = teil.fittingSize.width
            var aktuelle = zeilen[zeilen.count - 1]

            if teil is Gruppentrenner {
                // Breite der Gruppe dahinter, bis zum nächsten Trenner.
                var gruppe: CGFloat = 0
                var weiter = index + 1
                while weiter < sichtbar.count, !(sichtbar[weiter] is Gruppentrenner) {
                    gruppe += sichtbar[weiter].fittingSize.width + abstand
                    weiter += 1
                }
                let passtHier = breite <= 0 || x + w + abstand + gruppe - abstand <= breite
                let passtInZeile = breite <= 0 || gruppe - abstand <= breite
                if !aktuelle.isEmpty, !passtHier, passtInZeile {
                    zeilen.append([])
                    x = 0
                    index += 1
                    continue
                }
                if aktuelle.isEmpty {
                    index += 1
                    continue
                }
            } else if breite > 0, !aktuelle.isEmpty, x + w > breite {
                if aktuelle.last is Gruppentrenner {
                    aktuelle.removeLast()
                    zeilen[zeilen.count - 1] = aktuelle
                }
                zeilen.append([])
                x = 0
            }
            zeilen[zeilen.count - 1].append(teil)
            x += w + abstand
            index += 1
        }
        if setzen {
            let uebrig = Set(zeilen.flatMap { $0 }.map { ObjectIdentifier($0) })
            for teil in sichtbar where !uebrig.contains(ObjectIdentifier(teil)) {
                teil.frame = .zero
            }
        }

        var y: CGFloat = 0
        for (index, zeile) in zeilen.enumerated() {
            let zeilenhoehe = zeile.map { $0.fittingSize.height }.max() ?? 0
            var x: CGFloat = 0
            for teil in zeile {
                let groesse = teil.fittingSize
                if setzen {
                    teil.frame = NSRect(
                        x: x,
                        y: y + (zeilenhoehe - groesse.height) / 2,
                        width: groesse.width,
                        height: groesse.height
                    ).integral
                }
                x += groesse.width + abstand
            }
            y += zeilenhoehe + (index < zeilen.count - 1 ? zeilenabstand : 0)
        }
        return y
    }
}

/// Ein senkrechter Strich zwischen zwei Gruppen in einer `Fliessleiste`.
final class Gruppentrenner: NSView {

    override var intrinsicContentSize: NSSize { NSSize(width: 13, height: 18) }

    override func draw(_ bereich: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.midX.rounded(), y: 0, width: 1, height: bounds.height).fill()
    }
}
