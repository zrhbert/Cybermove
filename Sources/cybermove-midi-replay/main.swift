import CybermoveCore
import Foundation

// cybermove-midi-replay: play a captured MIDI stream through a virtual CoreMIDI
// source, paced like a real MIDI cable. It stands in for an Atari connected
// through a MIDI interface, so Cybermove's CoreMIDI input can be tried
// without hardware.
//
//   cybermove-midi-replay <capture.bin> [--name "Cybermove Test"] [--wait 5] [--loop]

func fail(_ text: String) -> Never {
    FileHandle.standardError.write(Data((text + "\n").utf8))
    exit(2)
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard let path = arguments.first, !path.hasPrefix("--") else {
    fail("usage: cybermove-midi-replay <capture.bin> [--name NAME] [--wait SECONDS] [--loop]")
}
arguments.removeFirst()

var name = "Cybermove Test"
var waitSeconds = 5.0
var loop = false
while let option = arguments.first {
    arguments.removeFirst()
    switch option {
    case "--loop":
        loop = true
    case "--name", "--wait":
        guard let value = arguments.first else { fail("\(option) needs a value") }
        arguments.removeFirst()
        if option == "--name" { name = value } else { waitSeconds = Double(value) ?? waitSeconds }
    default:
        fail("unknown option \(option)")
    }
}

guard let data = FileManager.default.contents(atPath: path) else { fail("cannot read \(path)") }
var parser = MidiParser()
let messages = parser.feed([UInt8](data))

let source: CoreMIDIVirtualSource
do {
    source = try CoreMIDIVirtualSource(name: name)
} catch {
    fail("cannot create the virtual source: \(error)")
}
print("virtual MIDI source \"\(name)\" (id \(source.uniqueID)) ready")
print("choose it in Cybermove; starting in \(Int(waitSeconds)) s")
try await Task.sleep(for: .seconds(waitSeconds))

// MIDI 1.0 runs at 31250 baud, 10 bits per byte: 3125 bytes per second.
let bytesPerSecond = 3125.0
repeat {
    let start = ContinuousClock.now
    var sent = 0.0
    var batch: [UInt32] = []
    var batchBytes = 0

    func flush() async throws {
        guard !batch.isEmpty else { return }
        source.send(words: batch)
        sent += Double(batchBytes)
        batch.removeAll(keepingCapacity: true)
        batchBytes = 0
        let due = start + .milliseconds(Int(sent / bytesPerSecond * 1000))
        try await Task.sleep(until: due)
    }

    for message in messages {
        let words = UMP.words(for: message)
        batch += words
        batchBytes += UMP.bytes(fromWords: words).count
        if batchBytes >= 150 { try await flush() }       // about 50 ms of cable time
    }
    try await flush()
    // Leave the source alive a moment: disposing it right after the last send
    // can drop the final packets before CoreMIDI has delivered them.
    try await Task.sleep(for: .milliseconds(500))
    print("replayed \(messages.count) messages")
} while loop
