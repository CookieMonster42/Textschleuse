import AppKit
import TextschleuseCore

let anwendung = NSApplication.shared

if CommandLine.arguments.contains("--selbsttest") {
    Selbsttest.laufen()
}

if CommandLine.arguments.contains("--bestand") {
    Bestandsbericht.laufen()
}

if let stelle = CommandLine.arguments.firstIndex(of: "--vorschau"),
   CommandLine.arguments.indices.contains(stelle + 1) {
    Vorschau.laufen(nach: CommandLine.arguments[stelle + 1])
}

let steuerung = Steuerung()
anwendung.delegate = steuerung
anwendung.setActivationPolicy(.accessory)
anwendung.run()
