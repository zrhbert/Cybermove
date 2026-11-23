import CoreMIDI
import Foundation

/// A MIDI input as CoreMIDI lists it: a USB interface port, a virtual source
/// from another app, and so on. The unique ID stays the same across restarts,
/// so it is what gets stored in the user's settings.
public struct CoreMIDIEndpoint: Identifiable, Hashable, Sendable {
    public let id: Int32
    public let name: String

    public init(id: Int32, name: String) {
        self.id = id
        self.name = name
    }
}

public enum CoreMIDIDevices {
    /// All MIDI sources currently known to the system.
    public static func sources() -> [CoreMIDIEndpoint] {
        (0..<MIDIGetNumberOfSources()).compactMap { index in
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0, let id = uniqueID(of: endpoint) else { return nil }
            return CoreMIDIEndpoint(id: id, name: displayName(of: endpoint))
        }
    }

    static func uniqueID(of object: MIDIObjectRef) -> Int32? {
        var id: Int32 = 0
        guard MIDIObjectGetIntegerProperty(object, kMIDIPropertyUniqueID, &id) == noErr else { return nil }
        return id
    }

    static func displayName(of object: MIDIObjectRef) -> String {
        var name: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(object, kMIDIPropertyDisplayName, &name) == noErr, let name {
            return name.takeRetainedValue() as String
        }
        return "MIDI source"
    }
}

/// MIDI bytes from CoreMIDI sources, for example an Atari connected through a
/// USB MIDI interface.
///
/// `sourceID` selects one source by its unique ID; `nil` listens to every
/// source. A source that is not there yet is picked up as soon as it appears,
/// so unplugging and replugging an interface works without restarting.
public struct CoreMIDIByteSource: MidiByteSource {
    public let sourceID: Int32?

    public init(sourceID: Int32? = nil) {
        self.sourceID = sourceID
    }

    public func bytes() -> AsyncStream<[UInt8]> {
        let sourceID = self.sourceID
        return AsyncStream { continuation in
            let session = CoreMIDIInputSession(sourceID: sourceID, continuation: continuation)
            continuation.onTermination = { _ in session.close() }
        }
    }
}

/// Owns the CoreMIDI client and input port for one stream.
final class CoreMIDIInputSession: @unchecked Sendable {
    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private let sourceID: Int32?
    private let continuation: AsyncStream<[UInt8]>.Continuation
    private let lock = NSLock()
    private var connected: Set<MIDIEndpointRef> = []
    private var closed = false

    init(sourceID: Int32?, continuation: AsyncStream<[UInt8]>.Continuation) {
        self.sourceID = sourceID
        self.continuation = continuation

        let clientStatus = MIDIClientCreateWithBlock("Cybermove" as CFString, &client) { [weak self] notification in
            switch notification.pointee.messageID {
            case .msgObjectAdded, .msgSetupChanged:
                self?.connectSources()
            default:
                break
            }
        }
        let portStatus = MIDIInputPortCreateWithProtocol(
            client, "Cybermove Input" as CFString, ._1_0, &port
        ) { [weak self] eventList, _ in
            self?.receive(eventList)
        }
        guard clientStatus == noErr, portStatus == noErr else {
            close()
            return
        }
        connectSources()
    }

    private func connectSources() {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        for index in 0..<MIDIGetNumberOfSources() {
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0, !connected.contains(endpoint) else { continue }
            if let sourceID, CoreMIDIDevices.uniqueID(of: endpoint) != sourceID { continue }
            if MIDIPortConnectSource(port, endpoint, nil) == noErr {
                connected.insert(endpoint)
            }
        }
    }

    private func receive(_ eventList: UnsafePointer<MIDIEventList>) {
        var words: [UInt32] = []
        for packet in eventList.unsafeSequence() {
            let count = Int(packet.pointee.wordCount)
            withUnsafeBytes(of: packet.pointee.words) { raw in
                words.append(contentsOf: raw.bindMemory(to: UInt32.self).prefix(count))
            }
        }
        let bytes = UMP.bytes(fromWords: words)
        if !bytes.isEmpty { continuation.yield(bytes) }
    }

    func close() {
        lock.lock()
        let wasClosed = closed
        closed = true
        lock.unlock()
        guard !wasClosed else { return }
        if port != 0 { MIDIPortDispose(port) }
        if client != 0 { MIDIClientDispose(client) }
        continuation.finish()
    }
}

/// A virtual MIDI source that other applications (including Cybermove itself)
/// see like a hardware input. Used by the tests and by `cybermove-midi-replay`
/// to stand in for an Atari that is connected through a MIDI interface.
public final class CoreMIDIVirtualSource: @unchecked Sendable {
    public struct CreationError: Error, CustomStringConvertible {
        public let status: OSStatus
        public var description: String { "CoreMIDI error \(status)" }
    }

    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()
    public let name: String
    public let uniqueID: Int32

    public init(name: String) throws {
        self.name = name
        var status = MIDIClientCreateWithBlock("Cybermove virtual" as CFString, &client) { _ in }
        guard status == noErr else { throw CreationError(status: status) }
        status = MIDISourceCreateWithProtocol(client, name as CFString, ._1_0, &source)
        guard status == noErr else { throw CreationError(status: status) }
        uniqueID = CoreMIDIDevices.uniqueID(of: source) ?? 0
    }

    deinit {
        if source != 0 { MIDIEndpointDispose(source) }
        if client != 0 { MIDIClientDispose(client) }
    }

    /// Sends raw MIDI 1.0 bytes. They are parsed first so that they can be
    /// converted to UMP words; bytes that do not form messages are dropped.
    public func send(bytes: [UInt8]) {
        var parser = MidiParser()
        let words = parser.feed(bytes).flatMap { UMP.words(for: $0) }
        send(words: words)
    }

    public func send(words: [UInt32]) {
        guard !words.isEmpty else { return }
        // 64 packets of at most two words need about 1.5 KB; the buffer is
        // larger, so the list never overflows and no capacity check is needed.
        let capacity = 4096
        let packetsPerList = 64
        let raw = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: MemoryLayout<UInt32>.alignment)
        defer { raw.deallocate() }
        let list = raw.assumingMemoryBound(to: MIDIEventList.self)

        var packet = MIDIEventListInit(list, ._1_0)
        var packetsInList = 0
        var index = 0
        while index < words.count {
            // Keep the words of one message together (sysex packets use two).
            let size = UMP.wordCount(messageType: words[index] >> 28)
            let end = min(index + size, words.count)
            let chunk = Array(words[index..<end])
            packet = MIDIEventListAdd(list, capacity, packet, 0, chunk.count, chunk)
            packetsInList += 1
            index = end
            if packetsInList == packetsPerList {
                MIDIReceivedEventList(source, list)
                packet = MIDIEventListInit(list, ._1_0)
                packetsInList = 0
            }
        }
        if packetsInList > 0 { MIDIReceivedEventList(source, list) }
    }
}
