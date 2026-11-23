import CybermoveCore
import Foundation
import Observation

/// Connects the engine to a FIFO and holds the user's display choices.
///
/// The engine is sampled by the views at a fixed rate, so this class only
/// publishes what changes rarely: whether it is running, the source path and
/// the display options.
@MainActor
@Observable
public final class MonitorController {
    public var fifoPath: String
    public private(set) var isRunning = false
    public private(set) var errorMessage: String?

    public var mode: GraphicsMode = .quadro
    public var selectedSystem = 0
    public var channels: [UInt8] = [14, 15] {
        didSet { engine.setChannels(channels) }
    }

    public let engine: MonitorEngine
    private var task: Task<Void, Never>?

    public init(fifoPath: String = "/tmp/cybermove.fifo", engine: MonitorEngine = MonitorEngine()) {
        self.fifoPath = fifoPath
        self.engine = engine
    }

    /// Create the FIFO if needed and start reading from it. Hatari is then
    /// started with `--midi-in /dev/null --midi-out <fifoPath>`.
    public func start() {
        guard task == nil else { return }
        errorMessage = nil
        if let problem = Self.prepare(path: fifoPath) {
            errorMessage = problem
            return
        }
        engine.reset()
        isRunning = true
        let engine = self.engine
        let source = FileByteSource(path: fifoPath, mode: .follow)
        task = Task {
            await engine.run(source)
            self.isRunning = false
            self.task = nil
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    /// Replay a capture file at full speed instead of following a FIFO.
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
