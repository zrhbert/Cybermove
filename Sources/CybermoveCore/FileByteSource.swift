import Foundation
import Synchronization

/// Reads raw MIDI bytes from a file or FIFO, for example the file given to
/// Hatari's `--midi-out`.
///
/// Two modes:
/// - `.untilEndOfFile`: blocks in `open` until a FIFO has a writer, reads until
///   the writer closes it (Hatari exited) and then finishes. Used by the
///   command-line tool and for replaying capture files.
/// - `.follow`: never finishes by itself. It waits for a writer, survives the
///   writer going away and coming back (Hatari restarts), and stops promptly
///   when the stream is cancelled. Used by the app.
public struct FileByteSource: MidiByteSource {
    public enum Mode: Sendable { case untilEndOfFile, follow }

    public let path: String
    public let chunkSize: Int
    public let mode: Mode

    public init(path: String, chunkSize: Int = 4096, mode: Mode = .untilEndOfFile) {
        self.path = path
        self.chunkSize = chunkSize
        self.mode = mode
    }

    public func bytes() -> AsyncStream<[UInt8]> {
        let path = self.path
        let chunkSize = self.chunkSize
        let mode = self.mode
        return AsyncStream { continuation in
            let cancelled = CancelFlag()
            continuation.onTermination = { _ in cancelled.cancel() }

            // A dedicated thread: blocking reads must not tie up the Swift
            // concurrency pool.
            let thread = Thread {
                switch mode {
                case .untilEndOfFile:
                    Self.readUntilEndOfFile(path: path, chunkSize: chunkSize, continuation: continuation)
                case .follow:
                    Self.follow(path: path, chunkSize: chunkSize, cancelled: cancelled, continuation: continuation)
                }
                continuation.finish()
            }
            thread.name = "Cybermove FileByteSource"
            thread.start()
        }
    }

    private static func readUntilEndOfFile(
        path: String, chunkSize: Int, continuation: AsyncStream<[UInt8]>.Continuation
    ) {
        let descriptor = open(path, O_RDONLY)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        while true {
            let count = read(descriptor, &buffer, chunkSize)
            if count <= 0 { return }
            continuation.yield(Array(buffer[0..<count]))
        }
    }

    private static func follow(
        path: String, chunkSize: Int, cancelled: CancelFlag,
        continuation: AsyncStream<[UInt8]>.Continuation
    ) {
        // O_NONBLOCK so that opening a FIFO without a writer returns at once
        // and the loop can notice a cancellation.
        let descriptor = open(path, O_RDONLY | O_NONBLOCK)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        var buffer = [UInt8](repeating: 0, count: chunkSize)

        while !cancelled.isCancelled {
            var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pollDescriptor, 1, 100)
            if ready < 0 {
                if errno == EINTR { continue }
                return
            }
            let count = read(descriptor, &buffer, chunkSize)
            if count > 0 {
                continuation.yield(Array(buffer[0..<count]))
            } else if count == 0 {
                usleep(50_000)          // no writer right now: wait for the next one
            } else if errno != EAGAIN && errno != EINTR {
                return
            }
        }
    }
}

private final class CancelFlag: Sendable {
    private let flag = Atomic<Bool>(false)
    var isCancelled: Bool { flag.load(ordering: .relaxed) }
    func cancel() { flag.store(true, ordering: .relaxed) }
}
