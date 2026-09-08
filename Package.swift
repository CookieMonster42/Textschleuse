// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Textschleuse",
    platforms: [.macOS(.v14)],
    products: [
        // Das Produkt heißt anders als das Target, damit die ausführbare Datei
        // im Bundle „Textschleuse" heißt und nicht „TextschleuseApp".
        .executable(name: "Textschleuse", targets: ["TextschleuseApp"]),
    ],
    targets: [
        .target(
            name: "TextschleuseCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "TextschleuseApp",
            dependencies: ["TextschleuseCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Kein `testTarget`: XCTest gehört zu Xcode, auf diesem Rechner sind
        // nur die Command Line Tools installiert. Die Prüfungen laufen deshalb
        // als eigenes Programm — `swift run Pruefungen`.
        .executableTarget(
            name: "Pruefungen",
            dependencies: ["TextschleuseCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
