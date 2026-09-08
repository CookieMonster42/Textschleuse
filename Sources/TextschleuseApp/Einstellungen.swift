import AppKit

/// Wo das Popup aufgeht.
enum PopupPosition: String, Codable, CaseIterable {
    case mauszeiger
    case bildschirmmitte
    case menueleiste

    var anzeigename: String {
        switch self {
        case .mauszeiger: return "Beim Mauszeiger"
        case .bildschirmmitte: return "Mitte des Bildschirms"
        case .menueleiste: return "Unter der Menüleiste"
        }
    }
}

/// Benutzereinstellungen. Liegen in den `UserDefaults`, nicht im
/// verschlüsselten Wörterbuch — hier steht nichts Schützenswertes.
final class Einstellungen {

    static let gemeinsam = Einstellungen()

    private let speicher = UserDefaults.standard
    private enum Schluessel {
        static let schuetzen = "kurzbefehl.schuetzen"
        static let rueckweg = "kurzbefehl.rueckweg"
        static let position = "popup.position"
        static let hinweiseMitkopieren = "clipboard.hinweise"
        static let backupErledigt = "backup.aufgefordert"
        static let backupPfad = "backup.pfad"
        static let nurMenueleiste = "darstellung.nurMenueleiste"
    }

    private init() {}

    var kurzbefehlSchuetzen: Tastenkombination {
        get { lies(Schluessel.schuetzen) ?? .schuetzen }
        set { schreib(newValue, unter: Schluessel.schuetzen) }
    }

    var kurzbefehlRueckweg: Tastenkombination {
        get { lies(Schluessel.rueckweg) ?? .rueckweg }
        set { schreib(newValue, unter: Schluessel.rueckweg) }
    }

    var popupPosition: PopupPosition {
        get {
            guard let roh = speicher.string(forKey: Schluessel.position),
                  let position = PopupPosition(rawValue: roh)
            else { return .mauszeiger }
            return position
        }
        set { speicher.set(newValue.rawValue, forKey: Schluessel.position) }
    }

    /// Der Hinweis für das Modell wandert mit in die Zwischenablage.
    var hinweiseMitkopieren: Bool {
        get { speicher.object(forKey: Schluessel.hinweiseMitkopieren) as? Bool ?? true }
        set { speicher.set(newValue, forKey: Schluessel.hinweiseMitkopieren) }
    }

    /// Wurde schon einmal zum Klartext-Backup aufgefordert?
    var backupAufgefordert: Bool {
        get { speicher.bool(forKey: Schluessel.backupErledigt) }
        set { speicher.set(newValue, forKey: Schluessel.backupErledigt) }
    }

    /// Aus heißt: Dock-Symbol und Menü oben. An heißt: nur das Symbol in der
    /// Menüleiste, so wie am Anfang.
    var nurMenueleiste: Bool {
        get { speicher.bool(forKey: Schluessel.nurMenueleiste) }
        set { speicher.set(newValue, forKey: Schluessel.nurMenueleiste) }
    }

    var backupPfad: URL? {
        get { speicher.url(forKey: Schluessel.backupPfad) }
        set { speicher.set(newValue, forKey: Schluessel.backupPfad) }
    }

    private func lies(_ schluessel: String) -> Tastenkombination? {
        guard let daten = speicher.data(forKey: schluessel) else { return nil }
        return try? JSONDecoder().decode(Tastenkombination.self, from: daten)
    }

    private func schreib(_ wert: Tastenkombination, unter schluessel: String) {
        guard let daten = try? JSONEncoder().encode(wert) else { return }
        speicher.set(daten, forKey: schluessel)
    }
}
