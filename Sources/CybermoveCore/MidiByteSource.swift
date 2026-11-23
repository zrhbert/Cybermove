/// A source of raw MIDI bytes. The Hatari FIFO is the first implementation; a
/// CoreMIDI source and, later, a bidirectional port adopt the same shape: the
/// byte stream is the only thing the parser and decoder depend on.
public protocol MidiByteSource: Sendable {
    func bytes() -> AsyncStream<[UInt8]>
}
