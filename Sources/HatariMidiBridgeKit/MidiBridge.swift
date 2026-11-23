import CybermoveCore
import Darwin
import Dispatch
import Foundation

/// Settings of a bridge.
public struct BridgeConfig: Sendable, Equatable {
    /// Hatari's `--midi-out` file: what the Atari sends.
    public var outFIFO: String
    /// Hatari's `--midi-in` file: what the Atari receives.
    public var inFIFO: String
    /// The CoreMIDI source other apps listen to for the Atari's output.
    public var sourceName = "Hatari MIDI Out"
    /// The CoreMIDI destination other apps send to for the Atari's input.
    public var destinationName = "Hatari MIDI In"
    /// CoreMIDI unique IDs for the two endpoints. Fixed IDs let apps that
    /// remember the endpoint by ID find it again after a restart.
    public var sourceUniqueID: Int32?
    public var destinationUniqueID: Int32?
    /// Leave out MIDI clock (F8) and active sensing (FE), in both directions.
    public var dropClock = false
    public var dropActiveSensing = false

    public static let defaultOutFIFO = "/tmp/hatari-midi-out.fifo"
    public static let defaultInFIFO = "/tmp/hatari-midi-in.fifo"
    public static let defaultSourceUniqueID: Int32 = 0x4841_4F31       // "HAO1"
    public static let defaultDestinationUniqueID: Int32 = 0x4841_4931  // "HAI1"

    public init(outFIFO: String = Self.defaultOutFIFO, inFIFO: String = Self.defaultInFIFO) {
        self.outFIFO = outFIFO
        self.inFIFO = inFIFO
    }
}

public enum BridgeDirection: Sendable {
    /// The Atari's output on its way to CoreMIDI.
    case fromHatari
    /// CoreMIDI's output on its way to the Atari.
    case toHatari
}

public struct BridgeError: Error, CustomStringConvertible, Equatable {
    public let description: String
}

/// Connects Hatari's MIDI files to CoreMIDI in both directions:
///
/// - Hatari writes `outFIFO`; the bridge parses it into MIDI messages and
///   publishes them on a virtual CoreMIDI source.
/// - Other apps send to a virtual CoreMIDI destination; the bridge writes the
///   bytes into `inFIFO`, which Hatari reads.
///
/// The bridge keeps its end of both FIFOs open, so Hatari can start and stop at
/// any time without blocking on an open, and Hatari's exit is not an end of
/// file for the bridge. Start the bridge before Hatari and keep it running.
///
/// For the FIFO Hatari reads, the bridge holds only a writing end. While
/// Hatari is not running, nobody reads that FIFO, so writing to it fails, and
/// the bridge throws the bytes away instead of letting them pile up and hit
/// the Atari, out of date, when Hatari starts.
public final class MidiBridge: @unchecked Sendable {
    public struct Statistics: Sendable, Equatable {
        public var bytesFromHatari = 0
        public var messagesFromHatari = 0
        public var bytesToHatari = 0
        /// Bytes for Hatari thrown away because Hatari was not running (nobody had
        /// its MIDI input open).
        public var discardedNoReader = 0
        /// Bytes for Hatari that did not fit in the FIFO.
        public var droppedFull = 0
    }

    public let config: BridgeConfig
    /// The unique IDs of the CoreMIDI endpoints, as the system assigned them.
    public let sourceID: Int32
    public let destinationID: Int32

    private let queue = DispatchQueue(label: "HatariMidiBridge")
    private let outFD: Int32
    private let inFD: Int32
    private var source: CoreMIDIVirtualSource?
    private var destination: CoreMIDIVirtualDestination?
    private var readSource: DispatchSourceRead?
    private var parser = MidiParser()
    private var statistics = Statistics()
    private var stopped = false
    private var hatariWasReading = true

    private let trace: (@Sendable (BridgeDirection, [UInt8]) -> Void)?
    private let log: (@Sendable (String) -> Void)?

    /// - Parameters:
    ///   - trace: called with the bytes passing through, after filtering
    ///   - log: called for notable events (discarded stale data, full FIFO)
    public init(config: BridgeConfig,
                trace: (@Sendable (BridgeDirection, [UInt8]) -> Void)? = nil,
                log: (@Sendable (String) -> Void)? = nil) throws {
        self.config = config
        self.trace = trace
        self.log = log
        outFD = try Self.openFIFO(config.outFIFO, access: O_RDWR)
        do {
            inFD = try Self.openFIFOForWritingOnly(config.inFIFO)
        } catch {
            close(outFD)
            throw error
        }

        do {
            let source = try CoreMIDIVirtualSource(name: config.sourceName, clientName: "HatariMidiBridge",
                                                   fixedUniqueID: config.sourceUniqueID)
            self.source = source
            sourceID = source.uniqueID
            // The handler needs `self`, which is not usable before every
            // property is set, so it goes through a box that learns the
            // bridge at the end of init.
            destination = try CoreMIDIVirtualDestination(
                name: config.destinationName, clientName: "HatariMidiBridge",
                fixedUniqueID: config.destinationUniqueID
            ) { [box] bytes in box.receive(bytes) }
            destinationID = destination?.uniqueID ?? 0
        } catch {
            close(outFD)
            close(inFD)
            throw BridgeError(description: "cannot create the CoreMIDI endpoints: \(error)")
        }

        let reader = DispatchSource.makeReadSource(fileDescriptor: outFD, queue: queue)
        reader.setEventHandler { [weak self] in self?.readFromHatari() }
        reader.resume()
        readSource = reader
        box.bridge = self
    }

    private final class ReceiverBox: @unchecked Sendable {
        weak var bridge: MidiBridge?
        func receive(_ bytes: [UInt8]) {
            guard let bridge else { return }
            bridge.queue.async { bridge.writeToHatari(bytes) }
        }
    }
    private let box = ReceiverBox()

    deinit { stop() }

    public func snapshot() -> Statistics {
        queue.sync { statistics }
    }

    /// Stop bridging and remove the CoreMIDI endpoints. The FIFOs stay in
    /// place, so that a restarted bridge uses the same files.
    public func stop() {
        queue.sync {
            guard !stopped else { return }
            stopped = true
            readSource?.cancel()
            readSource = nil
            source = nil
            destination = nil
            close(outFD)
            close(inFD)
        }
    }

    // MARK: - FIFOs

    private static func prepareFIFO(_ path: String) throws {
        var info = stat()
        if stat(path, &info) == 0 {
            guard info.st_mode & S_IFMT == S_IFIFO else {
                throw BridgeError(description: "\(path) exists and is not a FIFO")
            }
        } else if mkfifo(path, 0o600) != 0 {
            throw BridgeError(description: "cannot create the FIFO \(path): \(String(cString: strerror(errno)))")
        }
    }

    /// The FIFO Hatari writes: read-write, so that this end counts as the
    /// reader Hatari's open waits for, and as a writer, so that Hatari's exit
    /// does not look like an end of file.
    private static func openFIFO(_ path: String, access: Int32) throws -> Int32 {
        try prepareFIFO(path)
        let descriptor = open(path, access | O_NONBLOCK)
        guard descriptor >= 0 else {
            throw BridgeError(description: "cannot open \(path): \(String(cString: strerror(errno)))")
        }
        return descriptor
    }

    /// The FIFO Hatari reads: a writing end only. Opening for writing fails
    /// without a reader, so a reading end is opened first and closed again.
    /// Hatari's own open for reading finds this writer and does not block.
    private static func openFIFOForWritingOnly(_ path: String) throws -> Int32 {
        try prepareFIFO(path)
        let reader = open(path, O_RDONLY | O_NONBLOCK)
        guard reader >= 0 else {
            throw BridgeError(description: "cannot open \(path): \(String(cString: strerror(errno)))")
        }
        defer { close(reader) }
        let writer = open(path, O_WRONLY | O_NONBLOCK)
        guard writer >= 0 else {
            throw BridgeError(description: "cannot open \(path) for writing: \(String(cString: strerror(errno)))")
        }
        // Writing when Hatari is not there must give an error, not a signal.
        _ = fcntl(writer, F_SETNOSIGPIPE, 1)
        return writer
    }

    // MARK: - Hatari to CoreMIDI

    private func readFromHatari() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while !stopped {
            let count = read(outFD, &buffer, buffer.count)
            if count <= 0 { return }                    // EAGAIN: all read
            var bytes = Array(buffer[0..<count])
            statistics.bytesFromHatari += bytes.count
            bytes = filtered(bytes)
            // Messages, not raw bytes, go to CoreMIDI; the parser keeps its
            // state across reads, so a message split between two reads is fine.
            let messages = parser.feed(bytes)
            statistics.messagesFromHatari += messages.count
            source?.send(words: messages.flatMap { UMP.words(for: $0) })
            if !bytes.isEmpty { trace?(.fromHatari, bytes) }
        }
    }

    // MARK: - CoreMIDI to Hatari

    private func writeToHatari(_ received: [UInt8]) {
        guard !stopped else { return }
        let bytes = filtered(received)
        guard !bytes.isEmpty else { return }
        var offset = 0
        defer {
            statistics.bytesToHatari += offset
            if offset > 0 { trace?(.toHatari, Array(bytes[0..<offset])) }
        }
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { write(inFD, $0.baseAddress, $0.count) }
            if written > 0 {
                offset += written
                continue
            }
            switch errno {
            case EINTR:
                continue
            case EPIPE:
                // Nobody has the FIFO open for reading: Hatari is not running.
                let lost = bytes.count - offset
                statistics.discardedNoReader += lost
                if hatariWasReading { log?("Hatari is not running (nothing reads its MIDI input); discarding what is sent to it") }
                hatariWasReading = false
                return
            default:
                // EAGAIN: Hatari has the FIFO open but is not taking the bytes.
                let lost = bytes.count - offset
                statistics.droppedFull += lost
                log?("Hatari's MIDI input is full; dropped \(lost) bytes")
                hatariWasReading = true
                return
            }
        }
        hatariWasReading = true
    }

    // MARK: -

    private func filtered(_ bytes: [UInt8]) -> [UInt8] {
        guard config.dropClock || config.dropActiveSensing else { return bytes }
        return bytes.filter { byte in
            !(config.dropClock && byte == 0xF8) && !(config.dropActiveSensing && byte == 0xFE)
        }
    }
}
