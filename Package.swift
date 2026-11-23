// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cybermove",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CybermoveCore", targets: ["CybermoveCore"]),
        .executable(name: "cybermove-decode", targets: ["cybermove-decode"]),
    ],
    targets: [
        // MIDI byte parser, CMO-style decoder and input sources. No UI.
        .target(name: "CybermoveCore"),
        // Command-line tool: decode a captured MIDI stream or a live FIFO.
        .executableTarget(name: "cybermove-decode", dependencies: ["CybermoveCore"]),
        .testTarget(
            name: "CybermoveCoreTests",
            dependencies: ["CybermoveCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
