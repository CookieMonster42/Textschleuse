import AppKit
import TextschleuseCore

let anwendung = NSApplication.shared

if CommandLine.arguments.contains("--selbsttest") {
    Selbsttest.laufen()
}

let steuerung = Steuerung()
anwendung.delegate = steuerung
anwendung.setActivationPolicy(.accessory)
anwendung.run()
