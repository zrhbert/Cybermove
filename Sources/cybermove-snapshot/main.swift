import AppKit
import CybermoveCore
import CybermoveUI
import SwiftUI

// cybermove-snapshot: render the monitor window content to a PNG, from a
// capture file, without opening a window.
//
//   cybermove-snapshot <capture.bin> <out.png> [--fraction 0.5] [--mode okto] [--system 0]
//       [--yaw -30] [--pitch 20] [--roll 0] [--fov 30] [--zoom 1.2] [--crosshairs] [--volume-bars] [--numbers] [--no-lines] [--inside]

func fail(_ text: String) -> Never {
    FileHandle.standardError.write(Data((text + "\n").utf8))
    exit(2)
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2 else {
    fail("usage: cybermove-snapshot <capture.bin> <out.png> [--fraction 0.5] [--mode okto] [--system 0]")
}
let capturePath = arguments.removeFirst()
let outputPath = arguments.removeFirst()

var fraction = 0.5
var mode = GraphicsMode.quadro
var system = 0
var options = DisplayOptions()
while let option = arguments.first {
    arguments.removeFirst()
    // flags without a value
    switch option {
    case "--crosshairs": options.showCrosshairs = true; continue
    case "--volume-bars": options.showVolumeBars = true; continue
    case "--numbers": options.showSignalNumbers = true; continue
    case "--no-lines": options.showLines = false; continue
    case "--inside": options.insideView = true; continue
    case "--no-depth-cues": options.depthCues = false; continue
    case "--no-axes": options.showAxes = false; continue
    case "--no-fit": options.camera.fitToView = false; continue
    default: break
    }
    guard let value = arguments.first else { fail("\(option) needs a value") }
    arguments.removeFirst()
    switch option {
    case "--yaw": options.camera.yaw = Double(value) ?? options.camera.yaw
    case "--pitch": options.camera.pitch = Double(value) ?? options.camera.pitch
    case "--roll": options.camera.roll = Double(value) ?? options.camera.roll
    case "--fov": options.camera.fieldOfView = Double(value) ?? options.camera.fieldOfView
    case "--zoom": options.camera.zoom = Double(value) ?? options.camera.zoom
    case "--fraction": fraction = Double(value) ?? fraction
    case "--system": system = Int(value) ?? system
    case "--mode":
        guard let chosen = GraphicsMode.allCases.first(where: { $0.name.lowercased() == value.lowercased() }) else {
            fail("unknown mode \(value)")
        }
        mode = chosen
    default: fail("unknown option \(option)")
    }
}

guard let data = FileManager.default.contents(atPath: capturePath) else { fail("cannot read \(capturePath)") }
let engine = MonitorEngine()
engine.ingest([UInt8](data.prefix(Int(Double(data.count) * fraction))))

let content = MonitorContent(snapshot: engine.snapshot(), mode: mode, system: system, options: options)
    .frame(width: 900, height: 560)
    .background(Color(nsColor: .windowBackgroundColor))
let renderer = ImageRenderer(content: content)
renderer.scale = 2

guard let image = renderer.nsImage,
      let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fail("rendering failed")
}
do {
    try png.write(to: URL(fileURLWithPath: outputPath))
    print("wrote \(outputPath)")
} catch {
    fail("cannot write \(outputPath): \(error)")
}
