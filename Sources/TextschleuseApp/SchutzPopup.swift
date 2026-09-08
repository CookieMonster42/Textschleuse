import AppKit
import TextschleuseCore

/// Das schwebende Fenster, das der Kurzbefehl aufmacht.
///
/// Es hält nur die Arbeitsfläche und die Tastatur. Alles Fachliche steckt in
/// `SchutzAnsicht`, damit das Hauptfenster dasselbe zeigen kann.
final class SchutzPopup: TastaturPanel {

    enum Ausgang {
        /// Übernommen. `merken` heißt: die bestätigten Vermutungen wandern ins
        /// Wörterbuch.
        case uebernommen(Analyse, merken: Bool)
        case abgebrochen
    }

    private let ansicht: SchutzAnsicht
    private let abschluss: (Ausgang) -> Void

    init(analyse: Analyse, abschluss: @escaping (Ausgang) -> Void) {
        self.ansicht = SchutzAnsicht(analyse: analyse)
        self.abschluss = abschluss

        let bildschirm = TastaturPanel.bildschirmUnterMaus
        let maximal = TastaturPanel.maximaleGroesse(auf: bildschirm)
        super.init(groesse: NSSize(width: min(1000, maximal.width), height: min(640, maximal.height)))

        ansicht.beiUebernahme = { [weak self] analyse, merken in
            self?.abschluss(.uebernommen(analyse, merken: merken))
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
