import Foundation

/// Woher ein Fund stammt. Entscheidet über Farbe im Popup und darüber, ob du
/// zustimmen musst.
public enum Quelle: String, Sendable {
    /// Steht schon im Wörterbuch, behält seinen alten Platzhalter.
    case woerterbuch
    /// Regeltreffer wie IBAN oder E-Mail.
    case regel
    /// Vermutung aus Namensliste, Rechtsform oder Schreibmuster.
    case heuristik
}

/// Eine Stelle im Text, die ersetzt werden soll.
public struct Fund: Identifiable, Sendable {
    public let id: UUID
    /// Lage im Originaltext, gemessen in UTF-16-Einheiten (NSString-Zählweise).
    public var bereich: NSRange
    /// Der gefundene Wortlaut, so wie er im Text steht.
    public var text: String
    public var kategorie: Kategorie
    public var sicherheit: Sicherheit
    public var quelle: Quelle
    /// Gesetzt, wenn der Fund zu einem bestehenden Wörterbucheintrag gehört.
    public var eintragId: UUID?
    /// Der Platzhalter, der im Ergebnis stehen wird.
    public var platzhalter: String
    /// Vorschlag, dass dieser Fund als Alias zu einem bekannten Eintrag gehört.
    public var gruppenVorschlag: UUID?
    /// Vom Benutzer im Popup verworfen: bleibt im Klartext stehen.
    public var verworfen: Bool
    /// Vom Benutzer bestätigt: wird echt ersetzt statt als `UNBEKANNT_n`.
    public var bestaetigt: Bool

    public init(
        id: UUID = UUID(),
        bereich: NSRange,
        text: String,
        kategorie: Kategorie,
        sicherheit: Sicherheit,
        quelle: Quelle,
        eintragId: UUID? = nil,
        platzhalter: String = "",
        gruppenVorschlag: UUID? = nil,
        verworfen: Bool = false,
        bestaetigt: Bool = false
    ) {
        self.id = id
        self.bereich = bereich
        self.text = text
        self.kategorie = kategorie
        self.sicherheit = sicherheit
        self.quelle = quelle
        self.eintragId = eintragId
        self.platzhalter = platzhalter
        self.gruppenVorschlag = gruppenVorschlag
        self.verworfen = verworfen
        self.bestaetigt = bestaetigt
    }

    /// Muss dieser Fund von dir angesehen werden, bevor du Enter drückst?
    public var brauchtPruefung: Bool {
        sicherheit == .vermutung && !bestaetigt && !verworfen
    }
}

extension Array where Element == Fund {

    /// Wirft Überschneidungen raus. Es gewinnt der längere Fund, bei gleicher
    /// Länge der sicherere. So schlägt „Thorben Nyström" den Einzeltreffer
    /// „Thorben", und ein Wörterbucheintrag schlägt eine Vermutung.
    public func ohneUeberschneidungen() -> [Fund] {
        let sortiert = sorted { links, rechts in
            if links.bereich.length != rechts.bereich.length {
                return links.bereich.length > rechts.bereich.length
            }
            if links.rang != rechts.rang { return links.rang < rechts.rang }
            return links.bereich.location < rechts.bereich.location
        }

        var behalten: [Fund] = []
        for fund in sortiert {
            let kollidiert = behalten.contains { NSIntersectionRange($0.bereich, fund.bereich).length > 0 }
            if !kollidiert { behalten.append(fund) }
        }
        return behalten.sorted { $0.bereich.location < $1.bereich.location }
    }
}

extension Fund {
    /// Wörterbuch schlägt Regel schlägt Vermutung.
    fileprivate var rang: Int {
        switch quelle {
        case .woerterbuch: return 0
        case .regel: return 1
        case .heuristik: return 2
        }
    }
}
