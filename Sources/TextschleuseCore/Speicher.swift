import CryptoKit
import Foundation

public enum SpeicherFehler: LocalizedError {
    case schluesselNichtLesbar(OSStatus)
    case entschluesselnFehlgeschlagen
    case falscheVersion(Int)

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
        }
    }
}

/// Woher der Schlüssel kommt. Im Betrieb aus der Keychain; der Prüfstand
/// schiebt einen festen Schlüssel unter, weil ein unsigniertes Testprogramm
/// keinen Keychain-Zugriff bekommt.
public protocol Schluesselquelle: Sendable {
    func schluessel() throws -> SymmetricKey
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

    public init(ordner: URL? = nil, schluesselquelle: Schluesselquelle = KeychainSchluessel()) {
        if let ordner {
            self.ordner = ordner
        } else {
            let basis = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.ordner = basis.appendingPathComponent(Self.bundleId, isDirectory: true)
        }
        self.schluesselquelle = schluesselquelle
    }

    // MARK: Laden und Sichern

    public func laden() throws -> Woerterbuch {
        guard FileManager.default.fileExists(atPath: datei.path) else { return Woerterbuch() }
        let verschluesselt = try Data(contentsOf: datei)
        let schluessel = try schluesselHolenOderAnlegen()

        let klartext: Data
        do {
            let box = try AES.GCM.SealedBox(combined: verschluesselt)
            klartext = try AES.GCM.open(box, using: schluessel)
        } catch {
            throw SpeicherFehler.entschluesselnFehlgeschlagen
        }

        let buch = try JSONDecoder.textschleuse.decode(Woerterbuch.self, from: klartext)
        guard buch.version <= Woerterbuch.aktuelleVersion else {
            throw SpeicherFehler.falscheVersion(buch.version)
        }
        return buch
    }

    public func sichern(_ buch: Woerterbuch) throws {
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
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
        if let vorhanden = try lesen() { return vorhanden }
        let neu = SymmetricKey(size: .bits256)
        try schreiben(neu)
        return neu
    }

    private func lesen() throws -> SymmetricKey? {
        var frage: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Speicher.bundleId,
            kSecAttrAccount as String: Speicher.schluesselKonto,
            kSecReturnData as String: true,
        ]
        frage[kSecMatchLimit as String] = kSecMatchLimitOne

        var ergebnis: CFTypeRef?
        let status = SecItemCopyMatching(frage as CFDictionary, &ergebnis)
        switch status {
        case errSecSuccess:
            guard let daten = ergebnis as? Data else { return nil }
            return SymmetricKey(data: daten)
        case errSecItemNotFound:
            return nil
        default:
            throw SpeicherFehler.schluesselNichtLesbar(status)
        }
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
        SecItemDelete(eintrag as CFDictionary)
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
