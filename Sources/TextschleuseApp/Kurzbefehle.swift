import AppKit
import Carbon.HIToolbox

/// Eine Tastenkombination in Carbon-Zählweise. Wird so auch in den
/// Einstellungen gespeichert.
struct Tastenkombination: Codable, Equatable {
    var tastencode: UInt32
    /// Carbon-Flags: `cmdKey`, `optionKey`, `controlKey`, `shiftKey`.
    var zusatztasten: UInt32

    static let schuetzen = Tastenkombination(
        tastencode: UInt32(kVK_ANSI_S),
        zusatztasten: UInt32(controlKey | optionKey | cmdKey)
    )

    static let rueckweg = Tastenkombination(
        tastencode: UInt32(kVK_ANSI_R),
        zusatztasten: UInt32(controlKey | optionKey | cmdKey)
    )

    /// Lesbare Form für Menü und Einstellungen, etwa „⌃⌥⌘S".
    var beschriftung: String {
        var text = ""
        if zusatztasten & UInt32(controlKey) != 0 { text += "⌃" }
        if zusatztasten & UInt32(optionKey) != 0 { text += "⌥" }
        if zusatztasten & UInt32(shiftKey) != 0 { text += "⇧" }
        if zusatztasten & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + Self.tastenname(tastencode)
    }

    static func tastenname(_ code: UInt32) -> String {
        let tabelle: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
            kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
            kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
            kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
            kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_Space: "Leertaste", kVK_Return: "⏎", kVK_Escape: "⎋",
        ]
        return tabelle[Int(code)] ?? "Taste \(code)"
    }

    /// Rechnet die Flags aus einem `NSEvent` in Carbon-Flags um. Braucht die
    /// Aufnahme im Einstellungsfenster.
    static func carbonFlags(aus flags: NSEvent.ModifierFlags) -> UInt32 {
        var ergebnis: UInt32 = 0
        if flags.contains(.control) { ergebnis |= UInt32(controlKey) }
        if flags.contains(.option) { ergebnis |= UInt32(optionKey) }
        if flags.contains(.shift) { ergebnis |= UInt32(shiftKey) }
        if flags.contains(.command) { ergebnis |= UInt32(cmdKey) }
        return ergebnis
    }
}

/// Meldet globale Tastenkürzel bei Carbon an. Der Weg über
/// `RegisterEventHotKey` kommt ohne Bedienungshilfen-Recht aus; ein
/// Tastatur-Mitschnitt über einen Event-Tap bräuchte es.
final class Kurzbefehle {

    static let gemeinsam = Kurzbefehle()

    private var einbau: EventHandlerRef?
    private var verweise: [UInt32: EventHotKeyRef] = [:]
    private var aktionen: [UInt32: () -> Void] = [:]
    private var naechsteKennung: UInt32 = 1

    private init() {}

    func start() {
        guard einbau == nil else { return }
        var art = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), tastendruckEmpfangen, 1, &art, nil, &einbau)
    }

    /// Meldet eine Kombination an und liefert die Kennung, mit der man sie
    /// wieder abmelden kann. `nil`, wenn eine andere Anwendung sie schon
    /// belegt.
    @discardableResult
    func registriere(_ kombination: Tastenkombination, aktion: @escaping () -> Void) -> UInt32? {
        start()
        let kennung = naechsteKennung
        naechsteKennung += 1

        var verweis: EventHotKeyRef?
        let hotKeyId = EventHotKeyID(signature: OSType(0x54_53_4C_53), id: kennung)  // 'TSLS'
        let status = RegisterEventHotKey(
            kombination.tastencode,
            kombination.zusatztasten,
            hotKeyId,
            GetApplicationEventTarget(),
            0,
            &verweis
        )
        guard status == noErr, let verweis else { return nil }

        verweise[kennung] = verweis
        aktionen[kennung] = aktion
        return kennung
    }

    func entferne(_ kennung: UInt32) {
        if let verweis = verweise[kennung] { UnregisterEventHotKey(verweis) }
        verweise[kennung] = nil
        aktionen[kennung] = nil
    }

    func entferneAlle() {
        for kennung in Array(verweise.keys) { entferne(kennung) }
    }

    /// Prüft, ob eine Kombination frei ist: kurz anmelden, sofort wieder weg.
    func istFrei(_ kombination: Tastenkombination) -> Bool {
        var verweis: EventHotKeyRef?
        let hotKeyId = EventHotKeyID(signature: OSType(0x54_53_50_52), id: 0xFFFF)  // 'TSPR'
        let status = RegisterEventHotKey(
            kombination.tastencode,
            kombination.zusatztasten,
            hotKeyId,
            GetApplicationEventTarget(),
            0,
            &verweis
        )
        if status == noErr, let verweis {
            UnregisterEventHotKey(verweis)
            return true
        }
        return false
    }

    fileprivate func ausloesen(_ kennung: UInt32) {
        aktionen[kennung]?()
    }
}

/// C-Rückruf von Carbon. Muss eine freistehende Funktion ohne Kontext sein.
private let tastendruckEmpfangen: EventHandlerUPP = { _, ereignis, _ in
    guard let ereignis else { return OSStatus(eventNotHandledErr) }
    var kennung = EventHotKeyID()
    let status = GetEventParameter(
        ereignis,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &kennung
    )
    guard status == noErr else { return status }
    let kopie = kennung.id
    DispatchQueue.main.async {
        Kurzbefehle.gemeinsam.ausloesen(kopie)
    }
    return noErr
}
