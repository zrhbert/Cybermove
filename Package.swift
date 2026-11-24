// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cybermove",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CybermoveCore", targets: ["CybermoveCore"]),
        .library(name: "CybermoveUI", targets: ["CybermoveUI"]),
        .executable(name: "Cybermove", targets: ["Cybermove"]),
        .executable(name: "cybermove-decode", targets: ["cybermove-decode"]),
        .executable(name: "cybermove-snapshot", targets: ["cybermove-snapshot"]),
        .executable(name: "cybermove-midi-replay", targets: ["cybermove-midi-replay"]),
    ],
    targets: [
        // MIDI byte parser, CMO-style decoder, projection math and input sources. No UI.
        .target(name: "CybermoveCore"),
        // SwiftUI views and the controller that connects them to a source.
        .target(name: "CybermoveUI", dependencies: ["CybermoveCore"]),
        // The macOS app.
        .executableTarget(name: "Cybermove", dependencies: ["CybermoveUI"]),
        // Command-line tool: decode a captured MIDI stream or a live FIFO.
        .executableTarget(name: "cybermove-decode", dependencies: ["CybermoveCore"]),
        // Development tool: render the window to a PNG from a capture.
        .executableTarget(name: "cybermove-snapshot", dependencies: ["CybermoveUI"]),
        // Development tool: play a capture through a virtual CoreMIDI source.
        .executableTarget(name: "cybermove-midi-replay", dependencies: ["CybermoveCore"]),
        .testTarget(
            name: "CybermoveCoreTests",
            dependencies: ["CybermoveCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
