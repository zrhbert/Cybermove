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

var arguments = Array(CommandLine.arguments.dropFirst())
guard let path = arguments.first, !path.hasPrefix("--") else {
    fail("usage: cybermove-decode <file-or-fifo> [--events] [--channels 14,15]")
}
arguments.removeFirst()

var showEvents = false
var config = CybermoveConfig()
while let option = arguments.first {
    arguments.removeFirst()
    switch option {
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
        fail("unknown option \(option)")
    }
}

var parser = MidiParser()
var decoder = CybermoveDecoder(config: config)
var byteCount = 0
var messageCount = 0
var noteOns = 0
var stops = 0
var signalChanges = 0
var ignored = 0

for await chunk in FileByteSource(path: path).bytes() {
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
