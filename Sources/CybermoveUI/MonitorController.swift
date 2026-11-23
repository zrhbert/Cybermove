import CybermoveCore
import Foundation
import Observation
import Synchronization

/// Where the MIDI bytes come from.
public enum SourceChoice: Hashable, Sendable {
    /// A FIFO written by Hatari's `--midi-out`.
    case fifo
    /// Every CoreMIDI input.
    case allMIDIInputs
    /// One CoreMIDI input, by its unique ID.
    case midi(id: Int32)

    var storageValue: String {
        switch self {
        case .fifo: "fifo"
        case .allMIDIInputs: "all"
        case let .midi(id): "midi:\(id)"
        }
    }

    init?(storageValue: String) {
        switch storageValue {
        case "fifo": self = .fifo
        case "all": self = .allMIDIInputs
        default:
            guard storageValue.hasPrefix("midi:"), let id = Int32(storageValue.dropFirst(5)) else { return nil }
            self = .midi(id: id)
        }
    }
}

/// Connects the engine to a source and holds the user's choices.
///
/// The views redraw only when something changed: the engine reports arriving
/// data, and the controller then publishes a new `snapshot`, at most
/// `refreshRate` times a second. The rest (source, mode, display options,
/// whether data is flowing) is published when it changes. The choices are
/// stored in the user defaults.
@MainActor
@Observable
public final class MonitorController {
    public var fifoPath: String {
        didSet { defaults.set(fifoPath, forKey: Key.fifoPath) }
    }
    public var source: SourceChoice {
        didSet {
            defaults.set(source.storageValue, forKey: Key.source)
            if isRunning, source != oldValue {
                stop()
                start()
            }
        }
    }
    public var mode: GraphicsMode {
        didSet { defaults.set(mode.rawValue, forKey: Key.mode) }
    }
    public var options: DisplayOptions {
        didSet { defaults.set(options.storedJSON, forKey: Key.options) }
    }
    public var selectedSystem = 0
    public var channels: [UInt8] = [14, 15] {
        didSet { engine.setChannels(channels) }
    }

    /// The latest state of the signals; replaced when data arrives.
    public private(set) var snapshot: MonitorSnapshot
    /// True from the arrival of data until a second without any.
    public private(set) var isReceiving = false

    public private(set) var isRunning = false
    public private(set) var errorMessage: String?
    public private(set) var midiSources: [CoreMIDIEndpoint] = []

    public let engine: MonitorEngine
    private var task: Task<Void, Never>?
    private var silenceTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private let refreshPending = Mutex(false)

    /// Most snapshots published per second while data streams in.
    private nonisolated static let refreshRate = 30.0
    /// How long without data until the status changes from "receiving".
    private nonisolated static let silence = Duration.seconds(1.05)

    private enum Key {
        static let fifoPath = "fifoPath"
        static let source = "source"
        static let mode = "graphicsMode"
        static let options = "displayOptions"
    }

    public init(defaults: UserDefaults = .standard, engine: MonitorEngine = MonitorEngine()) {
        self.defaults = defaults
        self.engine = engine
        snapshot = engine.snapshot()
        fifoPath = defaults.string(forKey: Key.fifoPath) ?? "/tmp/cybermove.fifo"
        source = defaults.string(forKey: Key.source).flatMap(SourceChoice.init(storageValue:)) ?? .fifo
        mode = GraphicsMode(rawValue: defaults.integer(forKey: Key.mode)) ?? .quadro
        options = DisplayOptions(storedJSON: defaults.data(forKey: Key.options))
        refreshMIDISources()
        // Called from the reader thread: note that a refresh is due, and let
        // the main thread do it once per frame however many chunks arrived.
        engine.setChangeHandler { [weak self] in
            guard let self, self.refreshPending.withLock({ pending in
                defer { pending = true }
                return !pending
            }) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1 / Self.refreshRate) {
                MainActor.assumeIsolated { self.refresh() }
            }
        }
    }

    /// Publish the engine's current state.
    private func refresh() {
        refreshPending.withLock { $0 = false }
        let latest = engine.snapshot()
        snapshot = latest
        let receiving = latest.isReceiving(within: 1)
        if receiving != isReceiving { isReceiving = receiving }
        silenceTask?.cancel()
        guard receiving else { return }
        // Nothing arrives to trigger the next update, so ask for one.
        silenceTask = Task {
            try? await Task.sleep(for: Self.silence)
            if !Task.isCancelled { self.refresh() }
        }
    }

    /// The MIDI inputs to offer. A stored choice that is currently not
    /// connected stays in the list so the selection remains valid.
    public var offeredMIDISources: [CoreMIDIEndpoint] {
        var list = midiSources
        if case let .midi(id) = source, !list.contains(where: { $0.id == id }) {
            list.append(CoreMIDIEndpoint(id: id, name: "Unavailable input (\(id))"))
        }
        return list
    }

    public func refreshMIDISources() {
        let current = CoreMIDIDevices.sources()
        if current != midiSources { midiSources = current }
    }

    /// Start reading from the chosen source. For the FIFO the file is created
    /// if needed; Hatari is then started with
    /// `--midi-in /dev/null --midi-out <fifoPath>`.
    public func start() {
        guard task == nil else { return }
        errorMessage = nil
        let byteSource: any MidiByteSource
        switch source {
        case .fifo:
            if let problem = Self.prepare(path: fifoPath) {
                errorMessage = problem
                return
            }
            byteSource = FileByteSource(path: fifoPath, mode: .follow)
        case .allMIDIInputs:
            byteSource = CoreMIDIByteSource(sourceID: nil)
        case let .midi(id):
            byteSource = CoreMIDIByteSource(sourceID: id)
        }
        engine.reset()
        isRunning = true
        let engine = self.engine
        task = Task {
            await engine.run(byteSource)
            self.isRunning = false
            self.task = nil
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    /// Replay a capture file at full speed instead of following a source.
    public func load(captureAt url: URL, upToFraction fraction: Double = 1) {
        stop()
        engine.reset()
        guard let data = try? Data(contentsOf: url) else {
            errorMessage = "Cannot read \(url.lastPathComponent)"
            return
        }
        let count = Int(Double(data.count) * min(max(fraction, 0), 1))
        engine.ingest([UInt8](data.prefix(count)))
    }

    /// Returns a message when the path cannot be used.
    private static func prepare(path: String) -> String? {
        var info = stat()
        if stat(path, &info) == 0 { return nil }          // exists: FIFO or file
        if mkfifo(path, 0o600) == 0 { return nil }
        return "Cannot create FIFO at \(path): \(String(cString: strerror(errno)))"
    }
}
