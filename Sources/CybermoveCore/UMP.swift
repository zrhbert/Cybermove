/// Conversion between classic MIDI 1.0 bytes and Universal MIDI Packet (UMP)
/// words, the format CoreMIDI uses for its current API. Only the MIDI 1.0
/// subset is handled: system messages (type 1), MIDI 1.0 channel voice
/// messages (type 2) and 7-bit system exclusive (type 3). Other packet types
/// are skipped by their length.
public enum UMP {
    /// Number of 32-bit words in a packet of the given message type.
    static func wordCount(messageType: UInt32) -> Int {
        switch messageType {
        case 0x0, 0x1, 0x2, 0x6, 0x7: 1
        case 0x3, 0x4, 0x8, 0x9, 0xA: 2
        case 0xB, 0xC: 3
        default: 4          // 0x5 and 0xD...0xF
        }
    }

    // MARK: - UMP to MIDI 1.0 bytes

    /// The MIDI 1.0 byte stream for a sequence of UMP words. Words may hold
    /// several packets; a packet cut off at the end is dropped.
    public static func bytes(fromWords words: [UInt32]) -> [UInt8] {
        var out: [UInt8] = []
        var index = 0
        while index < words.count {
            let word = words[index]
            let type = word >> 28
            let size = wordCount(messageType: type)
            guard index + size <= words.count else { break }

            switch type {
            case 0x1:
                let status = UInt8((word >> 16) & 0xFF)
                let data1 = UInt8((word >> 8) & 0xFF)
                let data2 = UInt8(word & 0xFF)
                switch status {
                case 0xF1, 0xF3: out += [status, data1]
                case 0xF2: out += [status, data1, data2]
                default: out.append(status)                 // F6, F8 to FF
                }
            case 0x2:
                let status = UInt8((word >> 16) & 0xFF)
                let data1 = UInt8((word >> 8) & 0xFF)
                let data2 = UInt8(word & 0xFF)
                if status & 0xF0 == 0xC0 || status & 0xF0 == 0xD0 {
                    out += [status, data1]
                } else {
                    out += [status, data1, data2]
                }
            case 0x3:
                let part = (word >> 20) & 0xF                // 0 complete, 1 start, 2 continue, 3 end
                let count = min(Int((word >> 16) & 0xF), 6)
                let second = words[index + 1]
                let payload: [UInt8] = [
                    UInt8((word >> 8) & 0xFF), UInt8(word & 0xFF),
                    UInt8((second >> 24) & 0xFF), UInt8((second >> 16) & 0xFF),
                    UInt8((second >> 8) & 0xFF), UInt8(second & 0xFF),
                ]
                if part == 0 || part == 1 { out.append(0xF0) }
                out += payload.prefix(count)
                if part == 0 || part == 3 { out.append(0xF7) }
            default:
                break
            }
            index += size
        }
        return out
    }

    // MARK: - MIDI message to UMP words

    /// MIDI 1.0 UMP words for one message on group 0.
    public static func words(for message: MidiMessage) -> [UInt32] {
        func channel(_ statusHigh: UInt32, _ channel: UInt8, _ data1: UInt8, _ data2: UInt8) -> [UInt32] {
            [0x2 << 28 | (statusHigh | UInt32(channel & 0x0F)) << 16 | UInt32(data1) << 8 | UInt32(data2)]
        }
        func system(_ status: UInt32, _ data1: UInt8 = 0, _ data2: UInt8 = 0) -> [UInt32] {
            [0x1 << 28 | status << 16 | UInt32(data1) << 8 | UInt32(data2)]
        }

        switch message {
        case let .noteOff(c, note, velocity): return channel(0x80, c, note, velocity)
        case let .noteOn(c, note, velocity): return channel(0x90, c, note, velocity)
        case let .polyPressure(c, note, pressure): return channel(0xA0, c, note, pressure)
        case let .controlChange(c, controller, value): return channel(0xB0, c, controller, value)
        case let .programChange(c, program): return channel(0xC0, c, program, 0)
        case let .channelPressure(c, pressure): return channel(0xD0, c, pressure, 0)
        case let .pitchBend(c, value): return channel(0xE0, c, UInt8(value & 0x7F), UInt8((value >> 7) & 0x7F))
        case let .quarterFrame(value): return system(0xF1, value)
        case let .songPosition(value): return system(0xF2, UInt8(value & 0x7F), UInt8((value >> 7) & 0x7F))
        case let .songSelect(song): return system(0xF3, song)
        case .tuneRequest: return system(0xF6)
        case .clock: return system(0xF8)
        case .start: return system(0xFA)
        case .continue: return system(0xFB)
        case .stop: return system(0xFC)
        case .activeSensing: return system(0xFE)
        case .systemReset: return system(0xFF)
        case let .sysex(payload): return sysexWords(payload)
        }
    }

    private static func sysexWords(_ payload: [UInt8]) -> [UInt32] {
        var words: [UInt32] = []
        let chunks = stride(from: 0, to: max(payload.count, 1), by: 6).map {
            Array(payload[$0..<min($0 + 6, payload.count)])
        }
        for (index, chunk) in chunks.enumerated() {
            let part: UInt32
            if chunks.count == 1 { part = 0 }
            else if index == 0 { part = 1 }
            else if index == chunks.count - 1 { part = 3 }
            else { part = 2 }
            var padded = chunk + Array(repeating: 0, count: 6 - chunk.count)
            padded = padded.map { $0 & 0x7F }
            words.append(0x3 << 28 | part << 20 | UInt32(chunk.count) << 16
                         | UInt32(padded[0]) << 8 | UInt32(padded[1]))
            words.append(UInt32(padded[2]) << 24 | UInt32(padded[3]) << 16
                         | UInt32(padded[4]) << 8 | UInt32(padded[5]))
        }
        return words
    }
}
