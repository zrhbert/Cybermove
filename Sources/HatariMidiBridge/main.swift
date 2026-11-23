import CybermoveCore
import Dispatch
import Foundation
import HatariMidiBridgeKit

// HatariMidiBridge: connects Hatari's MIDI files to CoreMIDI, both ways.
//
//   Hatari --midi-out  ->  HatariMidiBridge  ->  CoreMIDI source "Hatari MIDI Out"
//   Hatari --midi-in   <-  HatariMidiBridge  <-  CoreMIDI destination "Hatari MIDI In"
//
// Start it first and leave it running; start Hatari with the options printed
// at startup. Any Mac MIDI app (a sequencer, Cybermove, a monitor) can then
// listen to the Atari and send to it.

func fail(_ text: String) -> Never {
    FileHandle.standardError.write(Data((text + "\n").utf8))
    exit(2)
}

let usage = """
    usage: HatariMidiBridge [options]
      --out-fifo PATH       Hatari's --midi-out file   (default \(BridgeConfig.defaultOutFIFO))
      --in-fifo PATH        Hatari's --midi-in file    (default \(BridgeConfig.defaultInFIFO))
      --source-name NAME    CoreMIDI source for the Atari's output   (default "Hatari MIDI Out")
      --destination-name NAME   CoreMIDI destination for the Atari's input   (default "Hatari MIDI In")
      --drop-clock          leave out MIDI clock (F8), both ways
      --drop-sensing        leave out active sensing (FE), both ways
      --events              print every message that passes through
      --quiet               print nothing but errors
      -h, --help            this text
    """

struct Options: Sendable {
    var config = BridgeConfig()
    var showEvents = false
    var quiet = false
}

func parseArguments() -> Options {
    var options = Options()
    options.config.sourceUniqueID = BridgeConfig.defaultSourceUniqueID
    options.config.destinationUniqueID = BridgeConfig.defaultDestinationUniqueID
    var arguments = Array(CommandLine.arguments.dropFirst())
    func value(for option: String) -> String {
        guard let next = arguments.first else { fail("\(option) needs a value\n\(usage)") }
        arguments.removeFirst()
        return next
    }
    while let option = arguments.first {
        arguments.removeFirst()
        switch option {
        case "--out-fifo": options.config.outFIFO = value(for: option)
        case "--in-fifo": options.config.inFIFO = value(for: option)
        case "--source-name": options.config.sourceName = value(for: option)
        case "--destination-name": options.config.destinationName = value(for: option)
        case "--drop-clock": options.config.dropClock = true
        case "--drop-sensing": options.config.dropActiveSensing = true
        case "--events": options.showEvents = true
        case "--quiet": options.quiet = true
        case "-h", "--help":
            print(usage)
            exit(0)
        default: fail("unknown option \(option)\n\(usage)")
        }
    }
    return options
}

// Writing to a FIFO nobody reads must give an error, not kill the bridge.
signal(SIGPIPE, SIG_IGN)

let options = parseArguments()
let config = options.config

func say(_ text: String) {
    if !options.quiet { print(text); fflush(stdout) }
}

/// Decodes the messages passing through, each direction with its own parser so
/// that they are decoded correctly across reads.
final class MessageTracer: @unchecked Sendable {
    private let lock = NSLock()
    private var parsers: [Bool: MidiParser] = [true: MidiParser(), false: MidiParser()]

    func trace(_ direction: BridgeDirection, _ bytes: [UInt8]) {
        let fromHatari = direction == .fromHatari
        lock.lock()
        let messages = parsers[fromHatari]?.feed(bytes) ?? []
        lock.unlock()
        for message in messages {
            print("\(fromHatari ? "Hatari -> Mac" : "Mac -> Hatari"): \(message)")
        }
        fflush(stdout)
    }
}

func makeTrace() -> (@Sendable (BridgeDirection, [UInt8]) -> Void)? {
    guard options.showEvents else { return nil }
    let tracer = MessageTracer()
    return { direction, bytes in tracer.trace(direction, bytes) }
}

let bridge: MidiBridge
do {
    bridge = try MidiBridge(
        config: config,
        trace: makeTrace(),
        log: { text in
            FileHandle.standardError.write(Data(("HatariMidiBridge: " + text + "\n").utf8))
        }
    )
} catch {
    fail("HatariMidiBridge: \(error)")
}

say("""
    HatariMidiBridge running.
      CoreMIDI source      "\(config.sourceName)" (id \(bridge.sourceID))       the Atari's output
      CoreMIDI destination "\(config.destinationName)" (id \(bridge.destinationID))   the Atari's input
    Start Hatari with:
      --midi-out \(config.outFIFO) --midi-in \(config.inFIFO)
    Press Ctrl-C to stop. Send SIGUSR1 (kill -USR1 \(getpid())) for the counters.
    """)

func printStatistics() {
    let s = bridge.snapshot()
    say("""
        from Hatari: \(s.bytesFromHatari) bytes, \(s.messagesFromHatari) messages
        to Hatari:   \(s.bytesToHatari) bytes, \(s.discardedNoReader) discarded (Hatari not running), \(s.droppedFull) dropped (FIFO full)
        """)
}

var signalSources: [DispatchSourceSignal] = []
for (signalNumber, action) in [(SIGINT, "stop"), (SIGTERM, "stop"), (SIGUSR1, "report")] {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler {
        if action == "report" {
            printStatistics()
        } else {
            printStatistics()
            bridge.stop()
            exit(0)
        }
    }
    source.resume()
    signalSources.append(source)
}

dispatchMain()
