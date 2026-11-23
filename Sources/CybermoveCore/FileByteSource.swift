import Foundation

/// A source of raw MIDI bytes. The Hatari FIFO is the first implementation; a
/// CoreMIDI source and, later, a bidirectional port can adopt the same shape
/// (the byte stream is the only thing the decoder depends on).
public protocol MidiByteSource: Sendable {
    func bytes() -> AsyncStream<[UInt8]>
}

/// Reads raw MIDI bytes from a file or FIFO, for example the file given to
/// Hatari's `--midi-out`. The stream ends at end of file; for a FIFO that is
/// when the writer closes it, i.e. when Hatari exits.
///
/// Opening a FIFO blocks until a writer opens it too, and Hatari blocks the
/// same way, so start this source first.
public struct FileByteSource: MidiByteSource {
    public let path: String
    public let chunkSize: Int

    public init(path: String, chunkSize: Int = 4096) {
        self.path = path
        self.chunkSize = chunkSize
    }

    public func bytes() -> AsyncStream<[UInt8]> {
        let path = self.path
        let chunkSize = self.chunkSize
        return AsyncStream { continuation in
            // A dedicated thread: read(2) on a FIFO blocks and must not tie up
            // the Swift concurrency pool.
            let thread = Thread {
                let descriptor = open(path, O_RDONLY)
                guard descriptor >= 0 else {
                    continuation.finish()
                    return
                }
                defer { close(descriptor) }
                var buffer = [UInt8](repeating: 0, count: chunkSize)
                while true {
                    let count = read(descriptor, &buffer, chunkSize)
                    if count <= 0 { break }
                    continuation.yield(Array(buffer[0..<count]))
                }
                continuation.finish()
            }
            thread.name = "Cybermove FileByteSource"
            thread.start()
        }
    }
}
