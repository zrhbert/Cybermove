import CybermoveCore
import Foundation

// cybermove-decode: decode a captured Realtimer MIDI stream, or follow a live
// FIFO that Hatari writes with --midi-out.
//
//   cybermove-decode <file-or-fifo> [--events] [--channels 14,15]

func fail(_ text: String) -> Never {
    FileHandle.standardError.write(Data((text + "\n").utf8))
    exit(2)
}

// Show each line as it happens, also when the output goes to a file or a pipe.
setvbuf(stdout, nil, _IOLBF, 0)

let usage = """
    usage: cybermove-decode <file-or-fifo> [--events] [--channels 14,15]
           cybermove-decode --coremidi [source-id] [--events] [--channels 14,15]
           cybermove-decode --list-midi
    """

var arguments = Array(CommandLine.arguments.dropFirst())
var path: String?
var useCoreMIDI = false
var coreMIDISourceID: Int32?
var showEvents = false
var config = CybermoveConfig()

while let option = arguments.first {
    arguments.removeFirst()
    switch option {
    case "--list-midi":
        let sources = CoreMIDIDevices.sources()
        if sources.isEmpty { print("no MIDI sources") }
        for source in sources { print("\(source.id)\t\(source.name)") }
        exit(0)
    case "--coremidi":
        useCoreMIDI = true
        if let next = arguments.first, let id = Int32(next) {
            coreMIDISourceID = id
            arguments.removeFirst()
        }
    case "--events":
        showEvents = true
    case "--channels":
        guard let list = arguments.first else { fail("--channels needs a list such as 14,15") }
        arguments.removeFirst()
        let channels = list.split(separator: ",").compactMap { UInt8($0) }
        guard !channels.isEmpty, channels.allSatisfy({ $0 < 16 }) else {
            fail("--channels expects 0-based channel numbers 0 to 15")
        }
        config = CybermoveConfig(channels: channels)
    default:
        if option.hasPrefix("--") || path != nil { fail("unknown option \(option)\n\(usage)") }
        path = option
    }
}

let byteSource: any MidiByteSource
if useCoreMIDI {
    byteSource = CoreMIDIByteSource(sourceID: coreMIDISourceID)
} else if let path {
    byteSource = FileByteSource(path: path)
} else {
    fail(usage)
}

var parser = MidiParser()
var decoder = CybermoveDecoder(config: config)
var byteCount = 0
var messageCount = 0
var noteOns = 0
var stops = 0
var signalChanges = 0
var ignored = 0

for await chunk in byteSource.bytes() {
    byteCount += chunk.count
    for message in parser.feed(chunk) {
        messageCount += 1
        switch message {
        case .noteOn: noteOns += 1
        case .stop: stops += 1
        default: ignored += 1
        }
        let update = decoder.apply(message)
        signalChanges += update.changes.count
        if showEvents {
            if update.didReset { print("stop: all signals reset") }
            for change in update.changes where !update.didReset {
                let a = change.after
                print("system \(change.system) signal \(change.signal): x=\(a.x) y=\(a.y) z=\(a.z) vol=\(a.volume)")
            }
        }
    }
}

print("bytes \(byteCount), messages \(messageCount), note-on \(noteOns), stop \(stops), other \(ignored), signal changes \(signalChanges)")
for (system, signals) in decoder.systems.enumerated() {
    let active = signals.enumerated().filter { $0.element != SignalState() }
    print("system \(system) (channel \(config.channels[system] + 1)): \(active.count) signals non-zero at end")
    for (signal, state) in active {
        print("  signal \(signal): x=\(state.x) y=\(state.y) z=\(state.z) vol=\(state.volume)")
    }
}
