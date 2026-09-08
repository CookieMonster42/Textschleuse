import AppKit
import TextschleuseCore

/// Das schwebende Fenster für den Rückweg. Hält nur Tastatur und Rahmen, die
/// Arbeitsfläche steckt in `RueckwegAnsicht`.
final class RueckwegPopup: TastaturPanel {

    enum Ausgang {
        case uebernommen(String)
        case abgebrochen
    }

    private let ansicht: RueckwegAnsicht
    private let abschluss: (Ausgang) -> Void

    /// Reicht eine Zuordnung nach oben, damit sie gespeichert wird.
    var beiWoerterbuchAenderung: ((Woerterbuch) -> Void)? {
        get { ansicht.beiWoerterbuchAenderung }
        set { ansicht.beiWoerterbuchAenderung = newValue }
    }

    init(
        ergebnis: RueckwegErgebnis,
        woerterbuch: Woerterbuch = Woerterbuch(),
        unbekannte: [String: String] = [:],
        abschluss: @escaping (Ausgang) -> Void
    ) {
        self.ansicht = RueckwegAnsicht(
            ergebnis: ergebnis,
            woerterbuch: woerterbuch,
            unbekannte: unbekannte
        )
        self.abschluss = abschluss

        let bildschirm = TastaturPanel.bildschirmUnterMaus
        let maximal = TastaturPanel.maximaleGroesse(auf: bildschirm)
        super.init(groesse: NSSize(width: min(1000, maximal.width), height: min(640, maximal.height)))

        ansicht.beiUebernahme = { [weak self] text in
            self?.abschluss(.uebernommen(text))
            self?.schliesseUndGibFokusZurueck()
        }
        ansicht.beiAbbruch = { [weak self] in
            self?.abschluss(.abgebrochen)
            self?.schliesseUndGibFokusZurueck()
        }

        ansicht.translatesAutoresizingMaskIntoConstraints = false
        let behaelter = NSView()
        behaelter.addSubview(ansicht)
        NSLayoutConstraint.activate([
            ansicht.topAnchor.constraint(equalTo: behaelter.topAnchor),
            ansicht.leadingAnchor.constraint(equalTo: behaelter.leadingAnchor),
            ansicht.trailingAnchor.constraint(equalTo: behaelter.trailingAnchor),
            ansicht.bottomAnchor.constraint(equalTo: behaelter.bottomAnchor),
        ])
        contentView = behaelter
    }

    override func keyDown(with ereignis: NSEvent) {
        if ansicht.verarbeite(ereignis) { return }
        super.keyDown(with: ereignis)
    }
}
