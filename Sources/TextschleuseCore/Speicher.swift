import CryptoKit
import Foundation

public enum SpeicherFehler: LocalizedError {
    case schluesselNichtLesbar(OSStatus)
    case entschluesselnFehlgeschlagen
    case falscheVersion(Int)
    case wuerdeSchrumpfen(vorher: Int, nachher: Int)

    public var errorDescription: String? {
        switch self {
        case .schluesselNichtLesbar(let status):
            return "Der Schlüssel aus der Keychain lässt sich nicht lesen (Status \(status))."
        case .entschluesselnFehlgeschlagen:
            return """
                Das Wörterbuch lässt sich nicht entschlüsseln. Der Schlüssel in der \
                Keychain gehört nicht zu dieser Datei. Ohne Klartext-Backup sind die \
                Einträge verloren.
                """
        case .falscheVersion(let version):
            return "Das Wörterbuch hat Version \(version) und ist neuer als dieses Programm."
        case .wuerdeSchrumpfen(let vorher, let nachher):
            return """
                Gespeichert werden sollen \(nachher) Einträge, in der Datei stehen \
                \(vorher). Das sieht nach einem Versehen aus und wurde angehalten.
                """
        }
    }
}

/// Woher der Schlüssel kommt. Im Betrieb aus der Keychain; der Prüfstand
/// schiebt einen festen Schlüssel unter, weil ein unsigniertes Testprogramm
/// keinen Keychain-Zugriff bekommt.
public protocol Schluesselquelle: Sendable {
    func schluessel() throws -> SymmetricKey
    /// Alle Schlüssel, die in Frage kommen. Normalerweise genau einer; mehr
    /// nur, wenn in der Keychain historisch mehrere gelandet sind.
    func alleSchluessel() throws -> [SymmetricKey]
    /// Wirft alle bis auf den übergebenen weg.
    func vereinheitliche(auf schluessel: SymmetricKey) throws
}

public extension Schluesselquelle {
    func alleSchluessel() throws -> [SymmetricKey] { [try schluessel()] }
    func vereinheitliche(auf schluessel: SymmetricKey) throws {}
}

/// Ein Schlüssel, der im Arbeitsspeicher steht. Nur für Prüfungen — auf der
/// Platte wäre er neben der verschlüsselten Datei wertlos.
public struct FesterSchluessel: Schluesselquelle {
    private let wert: SymmetricKey
    public init(_ wert: SymmetricKey = SymmetricKey(size: .bits256)) { self.wert = wert }
    public func schluessel() throws -> SymmetricKey { wert }
}

/// Legt das Wörterbuch verschlüsselt ab. Der Schlüssel liegt in der Keychain,
/// die Datei im Programmordner. Ohne Keychain-Eintrag ist die Datei wertlos —
/// deshalb fordert die App nach dem ersten Speichern zu einem Klartext-Export
/// auf.
public final class Speicher {

    public static let bundleId = "de.risiq.textschleuse"
    fileprivate static let schluesselKonto = "woerterbuch-schluessel"

    public let ordner: URL
    public var datei: URL { ordner.appendingPathComponent("woerterbuch.dat") }

    private let schluesselquelle: Schluesselquelle

    /// Der Ordner, in dem das echte Wörterbuch liegt. Nur die laufende App
    /// darf hier hinein. Prüfungen und Selbsttest bekommen einen Wegwerfordner
    /// übergeben — sonst würden sie am gelebten Bestand herumschreiben.
    public static var echterOrdner: URL {
        let basis = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return basis.appendingPathComponent(bundleId, isDirectory: true)
    }

    public init(ordner: URL? = nil, schluesselquelle: Schluesselquelle = KeychainSchluessel()) {
        self.ordner = ordner ?? Self.echterOrdner
        self.schluesselquelle = schluesselquelle
    }

    /// Zeigt dieser Speicher auf den echten Bestand?
    public var istEchterBestand: Bool {
        ordner.standardizedFileURL == Self.echterOrdner.standardizedFileURL
    }

    // MARK: Laden und Sichern

    public func laden() throws -> Woerterbuch {
        guard FileManager.default.fileExists(atPath: datei.path) else { return Woerterbuch() }
        let verschluesselt = try Data(contentsOf: datei)

        // Der Reihe nach alle Schlüssel probieren. Mehr als einer ist ein
        // Altlastenfall; wer passt, wird danach der einzige.
        let kandidaten = try schluesselquelle.alleSchluessel()
        var klartext: Data?
        var passender: SymmetricKey?
        for schluessel in kandidaten {
            guard let box = try? AES.GCM.SealedBox(combined: verschluesselt),
                  let versuch = try? AES.GCM.open(box, using: schluessel)
            else { continue }
            klartext = versuch
            passender = schluessel
            break
        }

        guard let klartext, let passender else {
            throw SpeicherFehler.entschluesselnFehlgeschlagen
        }
        if kandidaten.count > 1 {
            try? schluesselquelle.vereinheitliche(auf: passender)
        }

        let buch = try JSONDecoder.textschleuse.decode(Woerterbuch.self, from: klartext)
        guard buch.version <= Woerterbuch.aktuelleVersion else {
            throw SpeicherFehler.falscheVersion(buch.version)
        }
        return buch
    }

    /// Wo die automatischen Sicherungen liegen.
    public var sicherungsordner: URL { ordner.appendingPathComponent("sicherungen", isDirectory: true) }

    /// So viele Sicherungen bleiben liegen. Zwanzig reichen für einen
    /// Arbeitstag; sie sind je wenige Kilobyte groß.
    public static let sicherungenBehalten = 20

    /// Schreibt das Wörterbuch weg.
    ///
    /// Vorher zwei Vorkehrungen, beide aus einem konkreten Verlust heraus
    /// entstanden: die bisherige Datei wandert in den Sicherungsordner, und
    /// ein Bestand, der auf weniger als die Hälfte schrumpft, wird angehalten.
    /// Wer wirklich löschen will, setzt `auchWennKleiner`.
    public func sichern(_ buch: Woerterbuch, auchWennKleiner: Bool = false) throws {
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: datei.path) {
            let bisher = try? laden()
            if let bisher, !auchWennKleiner, wuerdeSchrumpfen(von: bisher, auf: buch) {
                throw SpeicherFehler.wuerdeSchrumpfen(
                    vorher: bisher.eintraege.count,
                    nachher: buch.eintraege.count
                )
            }
            try? legeSicherungAn()
        }

        let klartext = try JSONEncoder.textschleuse.encode(buch)
        let schluessel = try schluesselHolenOderAnlegen()
        let box = try AES.GCM.seal(klartext, using: schluessel)
        guard let verschluesselt = box.combined else { return }

        // Erst daneben schreiben, dann umbenennen. Ein Absturz mitten im
        // Schreiben soll nicht das ganze Wörterbuch zerlegen.
        let temp = datei.appendingPathExtension("neu")
        try verschluesselt.write(to: temp, options: [.atomic])
        _ = try FileManager.default.replaceItemAt(datei, withItemAt: temp)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: datei.path
        )
    }

    /// Wurde überhaupt schon einmal gespeichert? Steuert die einmalige
    /// Aufforderung zum Backup.
    public var hatDatei: Bool {
        FileManager.default.fileExists(atPath: datei.path)
    }

    // MARK: Sicherungen

    /// Verliert der neue Stand mehr als die Hälfte? Ein einzelner gelöschter
    /// Eintrag ist Alltag, ein Einbruch von 97 auf 4 nicht.
    func wuerdeSchrumpfen(von alt: Woerterbuch, auf neu: Woerterbuch) -> Bool {
        let vorher = alt.eintraege.count
        guard vorher > 0 else { return false }
        return neu.eintraege.count * 2 < vorher
    }

    /// Legt die aktuelle Datei als Kopie ab und räumt alte Kopien weg.
    func legeSicherungAn() throws {
        try FileManager.default.createDirectory(at: sicherungsordner, withIntermediateDirectories: true)
        let stempel = Self.stempelformat.string(from: Date())
        let ziel = sicherungsordner.appendingPathComponent("woerterbuch-\(stempel).dat")
        if !FileManager.default.fileExists(atPath: ziel.path) {
            try FileManager.default.copyItem(at: datei, to: ziel)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ziel.path)
        }

        let alte = sicherungen()
        for ueberzaehlig in alte.dropFirst(Self.sicherungenBehalten) {
            try? FileManager.default.removeItem(at: ueberzaehlig)
        }
    }

    /// Alle Sicherungen, neueste zuerst.
    public func sicherungen() -> [URL] {
        let inhalt = (try? FileManager.default.contentsOfDirectory(
            at: sicherungsordner,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return inhalt
            .filter { $0.pathExtension == "dat" }
            .sorted { links, rechts in
                let a = (try? links.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let b = (try? rechts.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return a > b
            }
    }

    /// Liest eine Sicherung, ohne sie zu übernehmen.
    public func lieseSicherung(_ pfad: URL) throws -> Woerterbuch {
        let verschluesselt = try Data(contentsOf: pfad)
        for schluessel in try schluesselquelle.alleSchluessel() {
            guard let box = try? AES.GCM.SealedBox(combined: verschluesselt),
                  let klartext = try? AES.GCM.open(box, using: schluessel)
            else { continue }
            return try JSONDecoder.textschleuse.decode(Woerterbuch.self, from: klartext)
        }
        throw SpeicherFehler.entschluesselnFehlgeschlagen
    }

    private static let stempelformat: DateFormatter = {
        let format = DateFormatter()
        // Millisekunden, weil mehrere Änderungen in derselben Sekunde
        // vorkommen. Ohne sie fiele jede Sicherung nach der ersten weg.
        format.dateFormat = "yyyy-MM-dd-HHmmss-SSS"
        format.locale = Locale(identifier: "de_DE")
        return format
    }()

    // MARK: Klartext

    /// Schreibt das Wörterbuch unverschlüsselt. Enthält echte Namen und
    /// Bankdaten — die Oberfläche sagt das vor dem Export deutlich.
    public func exportiereKlartext(_ buch: Woerterbuch, nach ziel: URL) throws {
        let daten = try JSONEncoder.textschleuseLesbar.encode(buch)
        try daten.write(to: ziel, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ziel.path)
    }

    public func importiereKlartext(von quelle: URL) throws -> Woerterbuch {
        let daten = try Data(contentsOf: quelle)
        return try JSONDecoder.textschleuse.decode(Woerterbuch.self, from: daten)
    }

    private func schluesselHolenOderAnlegen() throws -> SymmetricKey {
        try schluesselquelle.schluessel()
    }
}

// MARK: - Keychain

/// Der Betriebsfall: ein 256-Bit-Schlüssel im Anmeldeschlüsselbund. Er liegt
/// damit woanders als die verschlüsselte Datei und wandert nicht mit, wenn der
/// Programmordner in einem Backup oder in einer Support-Sammlung landet.
///
/// **Was das schützt und was nicht.** Die Datei allein ist wertlos: sie zu
/// kopieren bringt niemandem etwas. Gegen ein Programm, das unter deinem
/// Benutzer läuft, schützt das nicht — es kann den Schlüsselbund genauso
/// befragen wie die Textschleuse. Das ist eine bewusste Abwägung: die
/// Alternative wäre eine Zugriffsliste, die an der Codesignatur hängt, und die
/// bricht bei einer Ad-hoc-Signatur nach jedem Neubauen. Dann fragt macOS bei
/// jedem Start nach dem Anmeldekennwort.
///
/// Die Sec*-Funktionen für Zugriffslisten gelten als veraltet. Der Nachfolger,
/// der Data-Protection-Keychain, verlangt das Entitlement
/// `keychain-access-groups`, und das gilt nur mit einem echten
/// Entwicklerzertifikat — mit Ad-hoc-Signatur beendet macOS den Prozess sofort.
public struct KeychainSchluessel: Schluesselquelle {

    public init() {}

    public func schluessel() throws -> SymmetricKey {
        if let vorhanden = try alleSchluessel().first { return vorhanden }
        let neu = SymmetricKey(size: .bits256)
        try schreiben(neu)
        return neu
    }

    /// Fragt bewusst nach allen Treffern, nicht nach dem ersten.
    ///
    /// Eine frühere Fassung löschte vor dem Schreiben mit einem Suchmuster,
    /// das den Schlüsselwert enthielt — so ein Muster trifft nichts, und der
    /// Schreibvorgang legte einen zweiten Eintrag an. Mit `kSecMatchLimitOne`
    /// kam danach ein Fehler statt eines Schlüssels zurück.
    public func alleSchluessel() throws -> [SymmetricKey] {
        // Erst die Referenzen holen, dann für jede einzeln die Daten. Der
        // Datei-Schlüsselbund kann `kSecReturnData` nicht mit
        // `kSecMatchLimitAll` zusammen — das gibt Status -50.
        var frage = Self.grundmuster
        frage[kSecReturnRef as String] = true
        frage[kSecMatchLimit as String] = kSecMatchLimitAll

        var ergebnis: CFTypeRef?
        let status = SecItemCopyMatching(frage as CFDictionary, &ergebnis)
        switch status {
        case errSecItemNotFound:
            return []
        case errSecSuccess:
            break
        default:
            throw SpeicherFehler.schluesselNichtLesbar(status)
        }

        let referenzen: [CFTypeRef]
        if let liste = ergebnis as? [CFTypeRef] {
            referenzen = liste
        } else if let einzeln = ergebnis {
            referenzen = [einzeln]
        } else {
            return []
        }

        return referenzen.compactMap { referenz in
            var datenFrage: [String: Any] = [
                kSecValueRef as String: referenz,
                kSecReturnData as String: true,
            ]
            datenFrage[kSecClass as String] = kSecClassGenericPassword
            var daten: CFTypeRef?
            guard SecItemCopyMatching(datenFrage as CFDictionary, &daten) == errSecSuccess,
                  let roh = daten as? Data, roh.count == 32
            else { return nil }
            return SymmetricKey(data: roh)
        }
    }

    public func vereinheitliche(auf schluessel: SymmetricKey) throws {
        SecItemDelete(Self.grundmuster as CFDictionary)
        try schreiben(schluessel)
    }

    /// Das Suchmuster ohne Wert und ohne Zugriffsliste. Beides gehört ins
    /// Schreiben, nicht ins Suchen — sonst trifft die Suche nichts.
    private static var grundmuster: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Speicher.bundleId,
            kSecAttrAccount as String: Speicher.schluesselKonto,
        ]
    }

    private func schreiben(_ schluessel: SymmetricKey) throws {
        let daten = schluessel.withUnsafeBytes { Data($0) }
        var eintrag: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Speicher.bundleId,
            kSecAttrAccount as String: Speicher.schluesselKonto,
            kSecValueData as String: daten,
        ]
        if let zugriff = Self.zugriffOhneRueckfrage() {
            eintrag[kSecAttrAccess as String] = zugriff
        }
        SecItemDelete(Self.grundmuster as CFDictionary)
        let status = SecItemAdd(eintrag as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SpeicherFehler.schluesselNichtLesbar(status)
        }
    }

    /// Eine Zugriffsliste ohne eingetragene Programme. Leere Liste heißt für
    /// den Schlüsselbund: alle dürfen, ohne Rückfrage.
    private static func zugriffOhneRueckfrage() -> SecAccess? {
        let name = "Textschleuse Wörterbuch" as CFString
        var zugriff: SecAccess?
        guard SecAccessCreate(name, nil, &zugriff) == errSecSuccess, let zugriff else { return nil }

        var liste: CFArray?
        guard SecAccessCopyACLList(zugriff, &liste) == errSecSuccess,
              let eintraege = liste as? [SecACL]
        else { return nil }

        for eintrag in eintraege {
            SecACLSetContents(eintrag, nil, name, SecKeychainPromptSelector())
        }
        return zugriff
    }
}

extension JSONEncoder {
    static var textschleuse: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var textschleuseLesbar: JSONEncoder {
        let encoder = textschleuse
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var textschleuse: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
