/// Position and volume of one Cybermove signal.
///
/// Coordinates are signed offsets around the centre: the wire value minus 64,
/// so a MIDI velocity of 64 is 0, 0 is -64 and 127 is +63 (CMO's
/// `MIDI_TO_INTERN`). Volume is the raw wire value, 0 to 127.
public struct SignalState: Equatable, Sendable {
    public var x: Int8 = 0
    public var y: Int8 = 0
    public var z: Int8 = 0
    public var volume: UInt8 = 0

    public init(x: Int8 = 0, y: Int8 = 0, z: Int8 = 0, volume: UInt8 = 0) {
        self.x = x; self.y = y; self.z = z; self.volume = volume
    }
}

/// The four values carried per signal. Raw value is the low two pitch bits.
public enum Axis: UInt8, CaseIterable, Sendable {
    case x = 0, y = 1, z = 2, volume = 3
}

/// Which MIDI channel feeds which Cybermove system.
///
/// Realtimer sends each CMI system on its own channel (the CMI setup dialog
/// picks them). Channels are 0 based here, so 14 and 15 are MIDI channels
/// 15 and 16, the ones seen in a captured play session.
public struct CybermoveConfig: Equatable, Sendable {
    public var channels: [UInt8]

    public init(channels: [UInt8] = [14, 15]) {
        self.channels = channels
    }
}

public struct SignalChange: Equatable, Sendable {
    public let system: Int
    public let signal: Int
    public let before: SignalState
    public let after: SignalState
}

public struct DecodeUpdate: Equatable, Sendable {
    public var changes: [SignalChange] = []
    /// True when a MIDI Stop zeroed every signal.
    public var didReset = false
    public var isEmpty: Bool { changes.isEmpty && !didReset }
}

/// Decodes Realtimer's Cybermove MIDI output, following CMO's receive code:
///
/// - Note On: pitch = signal * 4 + axis, velocity = value, channel = system.
/// - MIDI Stop resets all coordinates and volumes to zero.
/// - Everything else (note off, clock, sysex, ...) is ignored, like CMO does.
public struct CybermoveDecoder: Sendable {
    public static let signalsPerSystem = 32

    public var config: CybermoveConfig
    public private(set) var systems: [[SignalState]]

    public init(config: CybermoveConfig = CybermoveConfig()) {
        self.config = config
        self.systems = Array(
            repeating: Array(repeating: SignalState(), count: Self.signalsPerSystem),
            count: config.channels.count
        )
    }

    @discardableResult
    public mutating func apply(_ message: MidiMessage) -> DecodeUpdate {
        switch message {
        case let .noteOn(channel, note, velocity):
            return applyNote(channel: channel, note: note, value: velocity)
        case .stop:
            return reset()
        default:
            return DecodeUpdate()
        }
    }

    private mutating func applyNote(channel: UInt8, note: UInt8, value: UInt8) -> DecodeUpdate {
        var update = DecodeUpdate()
        guard note < 128, value < 128 else { return update }
        let signal = Int(note >> 2)
        guard let axis = Axis(rawValue: note & 3) else { return update }

        for (system, systemChannel) in config.channels.enumerated() where systemChannel == channel {
            let before = systems[system][signal]
            var after = before
            switch axis {
            case .x: after.x = Int8(Int(value) - 64)
            case .y: after.y = Int8(Int(value) - 64)
            case .z: after.z = Int8(Int(value) - 64)
            case .volume: after.volume = value
            }
            if after != before {
                systems[system][signal] = after
                update.changes.append(SignalChange(system: system, signal: signal, before: before, after: after))
            }
        }
        return update
    }

    private mutating func reset() -> DecodeUpdate {
        var update = DecodeUpdate(didReset: true)
        for system in systems.indices {
            for signal in systems[system].indices where systems[system][signal] != SignalState() {
                update.changes.append(SignalChange(
                    system: system, signal: signal,
                    before: systems[system][signal], after: SignalState()))
                systems[system][signal] = SignalState()
            }
        }
        return update
    }
}
