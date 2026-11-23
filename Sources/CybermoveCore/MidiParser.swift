/// Incremental MIDI byte-stream parser.
///
/// Handles running status, system real-time bytes interleaved inside other
/// messages (they never disturb the message being assembled), system common
/// messages (which cancel running status) and system exclusive. Garbage data
/// bytes without a status are dropped. The parser keeps state between calls,
/// so a stream may be fed in arbitrary chunks.
public struct MidiParser: Sendable {
    private var status: UInt8 = 0      // status of the message being assembled
    private var running: UInt8 = 0     // voice status valid for running status
    private var needed = 0
    private var data: [UInt8] = []
    private var sysex: [UInt8]?

    public init() {}

    public mutating func feed<S: Sequence>(_ bytes: S) -> [MidiMessage] where S.Element == UInt8 {
        var out: [MidiMessage] = []
        for byte in bytes {
            if let message = push(byte) { out.append(message) }
        }
        return out
    }

    public mutating func push(_ byte: UInt8) -> MidiMessage? {
        if byte >= 0xF8 { return realtime(byte) }
        if byte & 0x80 != 0 { return beginMessage(byte) }
        return dataByte(byte)
    }

    // MARK: - Status bytes

    private func realtime(_ byte: UInt8) -> MidiMessage? {
        switch byte {
        case 0xF8: return .clock
        case 0xFA: return .start
        case 0xFB: return .continue
        case 0xFC: return .stop
        case 0xFE: return .activeSensing
        case 0xFF: return .systemReset
        default: return nil   // F9 and FD are undefined
        }
    }

    private mutating func beginMessage(_ byte: UInt8) -> MidiMessage? {
        // Any status byte ends a running sysex; F7 completes it, others abort it.
        if let payload = sysex {
            sysex = nil
            if byte == 0xF7 {
                resetAssembly(clearRunning: true)
                return .sysex(payload)
            }
        }
        data.removeAll(keepingCapacity: true)

        switch byte {
        case 0x80...0xEF:
            status = byte
            running = byte
            needed = (byte & 0xF0 == 0xC0 || byte & 0xF0 == 0xD0) ? 1 : 2
            return nil
        case 0xF0:
            sysex = []
            resetAssembly(clearRunning: true)
            return nil
        case 0xF1, 0xF3:
            status = byte; running = 0; needed = 1
            return nil
        case 0xF2:
            status = byte; running = 0; needed = 2
            return nil
        case 0xF6:
            resetAssembly(clearRunning: true)
            return .tuneRequest
        default:                // F4, F5 undefined; stray F7
            resetAssembly(clearRunning: true)
            return nil
        }
    }

    private mutating func resetAssembly(clearRunning: Bool) {
        status = 0
        needed = 0
        data.removeAll(keepingCapacity: true)
        if clearRunning { running = 0 }
    }

    // MARK: - Data bytes

    private mutating func dataByte(_ byte: UInt8) -> MidiMessage? {
        if sysex != nil {
            sysex?.append(byte)
            return nil
        }
        if status == 0 {
            guard running != 0 else { return nil }      // no status to attach to
            status = running
            needed = (running & 0xF0 == 0xC0 || running & 0xF0 == 0xD0) ? 1 : 2
        }
        data.append(byte)
        guard data.count == needed else { return nil }

        let message = build()
        data.removeAll(keepingCapacity: true)
        if status >= 0xF0 { status = 0 }                // system common: no running status
        return message
    }

    private func build() -> MidiMessage? {
        let channel = status & 0x0F
        switch status & 0xF0 {
        case 0x80: return .noteOff(channel: channel, note: data[0], velocity: data[1])
        case 0x90: return .noteOn(channel: channel, note: data[0], velocity: data[1])
        case 0xA0: return .polyPressure(channel: channel, note: data[0], pressure: data[1])
        case 0xB0: return .controlChange(channel: channel, controller: data[0], value: data[1])
        case 0xC0: return .programChange(channel: channel, program: data[0])
        case 0xD0: return .channelPressure(channel: channel, pressure: data[0])
        case 0xE0: return .pitchBend(channel: channel, value: UInt16(data[0]) | UInt16(data[1]) << 7)
        default:
            switch status {
            case 0xF1: return .quarterFrame(data[0])
            case 0xF2: return .songPosition(UInt16(data[0]) | UInt16(data[1]) << 7)
            case 0xF3: return .songSelect(data[0])
            default: return nil
            }
        }
    }
}
