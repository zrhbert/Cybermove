/// A decoded MIDI message. Note On with velocity 0 is deliberately NOT turned
/// into a note off: Cybermove's wire format uses the velocity as a plain value,
/// and zero is a legitimate value (for example volume 0).
public enum MidiMessage: Equatable, Sendable {
    case noteOff(channel: UInt8, note: UInt8, velocity: UInt8)
    case noteOn(channel: UInt8, note: UInt8, velocity: UInt8)
    case polyPressure(channel: UInt8, note: UInt8, pressure: UInt8)
    case controlChange(channel: UInt8, controller: UInt8, value: UInt8)
    case programChange(channel: UInt8, program: UInt8)
    case channelPressure(channel: UInt8, pressure: UInt8)
    case pitchBend(channel: UInt8, value: UInt16)

    case quarterFrame(UInt8)
    case songPosition(UInt16)
    case songSelect(UInt8)
    case tuneRequest

    case clock
    case start
    case `continue`
    case stop
    case activeSensing
    case systemReset

    /// System exclusive payload, without the F0 and F7 framing bytes.
    case sysex([UInt8])
}
