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
        .executable(name: "cybermove-midi-send", targets: ["cybermove-midi-send"]),
        .library(name: "HatariMidiBridgeKit", targets: ["HatariMidiBridgeKit"]),
        .executable(name: "HatariMidiBridge", targets: ["HatariMidiBridge"]),
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
        // Development tool: send MIDI bytes to a CoreMIDI destination.
        .executableTarget(name: "cybermove-midi-send", dependencies: ["CybermoveCore"]),
        // The bridge between Hatari's MIDI files (FIFOs) and CoreMIDI, in both directions.
        .target(name: "HatariMidiBridgeKit", dependencies: ["CybermoveCore"]),
        // The headless command-line / LaunchAgent program built on it.
        .executableTarget(name: "HatariMidiBridge", dependencies: ["HatariMidiBridgeKit"]),
        .testTarget(
            name: "HatariMidiBridgeKitTests",
            dependencies: ["HatariMidiBridgeKit", "CybermoveCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "CybermoveCoreTests",
            dependencies: ["CybermoveCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
