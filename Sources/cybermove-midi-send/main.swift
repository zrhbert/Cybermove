import CybermoveCore
import Foundation

// cybermove-midi-send: send MIDI bytes to a CoreMIDI destination, for example
// the HatariMidiBridge's "Hatari MIDI In".
//
//   cybermove-midi-send --list
//   cybermove-midi-send <destination id or part of its name> <hex byte>... [--repeat N]
//
//   cybermove-midi-send "Hatari MIDI In" FA 90 3C 64 FC

func fail(_ text: String) -> Never {
    FileHandle.standardError.write(Data((text + "\n").utf8))
    exit(2)
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard let first = arguments.first else {
    fail("usage: cybermove-midi-send --list | <destination id or name> <hex byte>... [--repeat N]")
}
if first == "--list" {
    let destinations = CoreMIDIDevices.destinations()
    if destinations.isEmpty { print("no MIDI destinations") }
    for destination in destinations { print("\(destination.id)\t\(destination.name)") }
    exit(0)
}
arguments.removeFirst()

var repeatCount = 1
if let index = arguments.firstIndex(of: "--repeat") {
    guard index + 1 < arguments.count, let count = Int(arguments[index + 1]), count > 0 else {
        fail("--repeat needs a positive number")
    }
    repeatCount = count
    arguments.removeSubrange(index...(index + 1))
}

let destinations = CoreMIDIDevices.destinations()
let wanted = Int32(first).flatMap { id in destinations.first { $0.id == id } }
    ?? destinations.first { $0.name.localizedCaseInsensitiveContains(first) }
guard let destination = wanted else { fail("no MIDI destination matches \"\(first)\" (try --list)") }

let bytes = arguments.compactMap { UInt8($0, radix: 16) }
guard bytes.count == arguments.count, !bytes.isEmpty else { fail("the bytes must be hexadecimal, such as FA 90 3C 64") }

do {
    let sender = try CoreMIDISender()
    for _ in 0..<repeatCount {
        guard sender.send(bytes: bytes, toDestinationID: destination.id) else { fail("sending failed") }
    }
    print("sent \(bytes.count * repeatCount) bytes to \"\(destination.name)\"")
    try await Task.sleep(for: .milliseconds(200))
} catch {
    fail("cannot create the sender: \(error)")
}
