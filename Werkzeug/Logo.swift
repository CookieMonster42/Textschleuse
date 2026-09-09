// Zeichnet das Programmsymbol und schreibt ein .icns.
//
//     swift Werkzeug/Logo.swift .build/Textschleuse.icns
//
// Steht als Skript hier und nicht als Bilddatei im Verzeichnis, damit sich am
// Symbol etwas ändern lässt, ohne ein Zeichenprogramm zu öffnen — und damit
// im Repo kein Binärklumpen liegt, den niemand mehr nachvollziehen kann.
//
// Das Motiv: Text läuft links als Zeilen hinein, in der Mitte steht die
// Schleuse, rechts kommt er in Blöcken heraus. Also genau das, was das
// Programm tut.

import AppKit
import Foundation

let ziel = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : ".build/Textschleuse.icns"

// MARK: Farben

/// Verlauf von Magenta nach Violett nach Cyan. Auffällig genug, um im Dock
/// zwischen lauter blauen Programmsymbolen aufzufallen.
let verlauf = NSGradient(colors: [
    NSColor(srgbRed: 0.98, green: 0.24, blue: 0.55, alpha: 1),
    NSColor(srgbRed: 0.58, green: 0.24, blue: 0.92, alpha: 1),
    NSColor(srgbRed: 0.13, green: 0.72, blue: 0.94, alpha: 1),
], atLocations: [0, 0.52, 1], colorSpace: .sRGB)!

func zeichne(kante: CGFloat) -> NSImage {
    let bild = NSImage(size: NSSize(width: kante, height: kante))
    bild.lockFocus()
    defer { bild.unlockFocus() }

    NSGraphicsContext.current?.imageInterpolation = .high
    let e = kante / 1024  // alles in Anteilen der Kantenlänge

    // Apples Raster: das Symbol füllt nicht die ganze Fläche.
    let rand = 100 * e
    let flaeche = NSRect(x: rand, y: rand, width: kante - 2 * rand, height: kante - 2 * rand)
    let squircle = NSBezierPath(roundedRect: flaeche, xRadius: 185 * e, yRadius: 185 * e)
    verlauf.draw(in: squircle, angle: -55)

    // Ein heller Schimmer oben, damit die Fläche nicht flach wirkt.
    NSGraphicsContext.saveGraphicsState()
    squircle.setClip()
    let schimmer = NSGradient(
        starting: NSColor(white: 1, alpha: 0.28),
        ending: NSColor(white: 1, alpha: 0)
    )!
    schimmer.draw(in: NSRect(x: rand, y: kante * 0.52, width: flaeche.width, height: kante * 0.34), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    squircle.setClip()

    // Links: drei Zeilen Klartext, die hineinlaufen.
    NSColor(white: 1, alpha: 0.95).setFill()
    let zeilenHoehe = 46 * e
    let zeilen: [(CGFloat, CGFloat)] = [(600, 250), (512, 200), (424, 285)]
    for (y, breite) in zeilen {
        let stab = NSBezierPath(
            roundedRect: NSRect(x: 210 * e, y: y * e, width: breite * e, height: zeilenHoehe),
            xRadius: zeilenHoehe / 2,
            yRadius: zeilenHoehe / 2
        )
        stab.fill()
    }

    // Mitte: die Schleuse. Zwei Pfosten und ein Riegel dazwischen.
    let mitteX = 545 * e
    NSColor(white: 1, alpha: 0.98).setFill()
    for versatz in [CGFloat(-1), 1] {
        let pfosten = NSBezierPath(roundedRect: NSRect(
            x: mitteX + versatz * 44 * e - 15 * e,
            y: 330 * e,
            width: 30 * e,
            height: 380 * e
        ), xRadius: 15 * e, yRadius: 15 * e)
        pfosten.fill()
    }
    let riegel = NSBezierPath(roundedRect: NSRect(
        x: mitteX - 78 * e,
        y: 468 * e,
        width: 156 * e,
        height: 104 * e
    ), xRadius: 34 * e, yRadius: 34 * e)
    riegel.fill()

    // Der Schlitz im Riegel — macht aus dem Klotz ein Schloss.
    NSColor(srgbRed: 0.35, green: 0.20, blue: 0.62, alpha: 1).setFill()
    let schlitz = NSBezierPath(roundedRect: NSRect(
        x: mitteX - 13 * e,
        y: 494 * e,
        width: 26 * e,
        height: 52 * e
    ), xRadius: 13 * e, yRadius: 13 * e)
    schlitz.fill()

    // Rechts: dieselben Zeilen, jetzt in Blöcken — die Platzhalter.
    let blockFarben = [
        NSColor(srgbRed: 1, green: 0.85, blue: 0.30, alpha: 1),
        NSColor(srgbRed: 0.55, green: 1, blue: 0.72, alpha: 1),
        NSColor(white: 1, alpha: 0.95),
    ]
    for (index, (y, _)) in zeilen.enumerated() {
        var x = 660 * e
        for stueck in 0..<3 {
            let breite = (stueck == 1 ? 54 : 78) * e
            blockFarben[index].withAlphaComponent(stueck == 2 ? 0.75 : 1).setFill()
            let block = NSBezierPath(
                roundedRect: NSRect(x: x, y: y * e, width: breite, height: zeilenHoehe),
                xRadius: zeilenHoehe / 2,
                yRadius: zeilenHoehe / 2
            )
            block.fill()
            x += breite + 18 * e
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    return bild
}

// MARK: Schreiben

func schreibePNG(_ bild: NSImage, nach pfad: String) throws {
    guard let daten = bild.tiffRepresentation,
          let abbild = NSBitmapImageRep(data: daten),
          let png = abbild.representation(using: .png, properties: [:])
    else { throw NSError(domain: "Logo", code: 1) }
    try png.write(to: URL(fileURLWithPath: pfad))
}

let arbeitsordner = NSTemporaryDirectory() + "textschleuse-icon-\(UUID().uuidString)/Textschleuse.iconset"
try FileManager.default.createDirectory(atPath: arbeitsordner, withIntermediateDirectories: true)

// Die Namen sind vorgeschrieben; iconutil verlangt genau diese Liste.
let groessen: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]
for (kante, name) in groessen {
    try schreibePNG(zeichne(kante: CGFloat(kante)), nach: "\(arbeitsordner)/\(name)")
}

let werkzeug = Process()
werkzeug.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
werkzeug.arguments = ["-c", "icns", arbeitsordner, "-o", ziel]
try werkzeug.run()
werkzeug.waitUntilExit()
try? FileManager.default.removeItem(atPath: (arbeitsordner as NSString).deletingLastPathComponent)

guard werkzeug.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil ist mit \(werkzeug.terminationStatus) ausgestiegen\n".utf8))
    exit(1)
}
print("Symbol geschrieben: \(ziel)")
