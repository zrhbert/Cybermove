import Foundation
import Testing
@testable import CybermoveCore

// MARK: - Parser

@Suite struct MidiParserTests {
    @Test func parsesNoteOn() {
        var parser = MidiParser()
        #expect(parser.feed([0x9E, 0x60, 0x40]) == [.noteOn(channel: 14, note: 0x60, velocity: 0x40)])
    }

    @Test func noteOnWithVelocityZeroStaysNoteOn() {
        var parser = MidiParser()
        #expect(parser.feed([0x90, 60, 0]) == [.noteOn(channel: 0, note: 60, velocity: 0)])
    }

    @Test func runningStatusRepeatsTheStatus() {
        var parser = MidiParser()
        let messages = parser.feed([0x9F, 0, 0x40, 1, 0x41, 2, 0x42])
        #expect(messages == [
            .noteOn(channel: 15, note: 0, velocity: 0x40),
            .noteOn(channel: 15, note: 1, velocity: 0x41),
            .noteOn(channel: 15, note: 2, velocity: 0x42),
        ])
    }

    @Test func realtimeInsideAMessageDoesNotDisturbIt() {
        var parser = MidiParser()
        let messages = parser.feed([0x9F, 0x01, 0xF8, 0x40, 0xFC])
        #expect(messages == [.clock, .noteOn(channel: 15, note: 1, velocity: 0x40), .stop])
    }

    @Test func chunkedInputGivesTheSameResult() {
        var parser = MidiParser()
        var messages: [MidiMessage] = []
        for byte: UInt8 in [0x9E, 0x64, 0x7F, 0x9E, 0x65, 0x00] {
            messages += parser.feed([byte])
        }
        #expect(messages == [
            .noteOn(channel: 14, note: 0x64, velocity: 0x7F),
            .noteOn(channel: 14, note: 0x65, velocity: 0),
        ])
    }

    @Test func systemCommonCancelsRunningStatus() {
        var parser = MidiParser()
        // After a song select, bare data bytes have no status and are dropped.
        let messages = parser.feed([0x90, 60, 100, 0xF3, 5, 61, 100])
        #expect(messages == [.noteOn(channel: 0, note: 60, velocity: 100), .songSelect(5)])
    }

    @Test func sysexIsCollectedWithoutFraming() {
        var parser = MidiParser()
        #expect(parser.feed([0xF0, 0x7F, 0x01, 0x06, 0x02, 0xF7]) == [.sysex([0x7F, 0x01, 0x06, 0x02])])
    }

    @Test func statusByteAbortsAnUnfinishedSysex() {
        var parser = MidiParser()
        #expect(parser.feed([0xF0, 1, 2, 0x90, 60, 100]) == [.noteOn(channel: 0, note: 60, velocity: 100)])
    }

    @Test func parsesTransportAndPositionMessages() {
        var parser = MidiParser()
        #expect(parser.feed([0xFA, 0xFB, 0xFC, 0xF2, 0x01, 0x02, 0xF1, 0x23]) ==
                [.start, .continue, .stop, .songPosition(0x101), .quarterFrame(0x23)])
    }

    @Test func parsesTwoByteAndOneByteVoiceMessages() {
        var parser = MidiParser()
        #expect(parser.feed([0xC3, 7, 0xD1, 9, 0xE2, 0x01, 0x40]) == [
            .programChange(channel: 3, program: 7),
            .channelPressure(channel: 1, pressure: 9),
            .pitchBend(channel: 2, value: 1 | 0x40 << 7),
        ])
    }
}

// MARK: - Decoder

@Suite struct CybermoveDecoderTests {
    @Test func decodesSignalAxisAndValue() {
        var decoder = CybermoveDecoder()
        // pitch 96 = signal 24, axis X; velocity 100 = +36
        let update = decoder.apply(.noteOn(channel: 14, note: 96, velocity: 100))
        #expect(decoder.systems[0][24].x == 36)
        #expect(update.changes.count == 1)
        #expect(update.changes[0].signal == 24)
    }

    @Test func centreIsZeroAndRangeIsMinus64ToPlus63() {
        var decoder = CybermoveDecoder()
        decoder.apply(.noteOn(channel: 14, note: 1, velocity: 64))
        #expect(decoder.systems[0][0].y == 0)
        decoder.apply(.noteOn(channel: 14, note: 1, velocity: 0))
        #expect(decoder.systems[0][0].y == -64)
        decoder.apply(.noteOn(channel: 14, note: 1, velocity: 127))
        #expect(decoder.systems[0][0].y == 63)
    }

    @Test func volumeIsTheRawValue() {
        var decoder = CybermoveDecoder()
        decoder.apply(.noteOn(channel: 14, note: 3, velocity: 127))
        #expect(decoder.systems[0][0].volume == 127)
        decoder.apply(.noteOn(channel: 14, note: 3, velocity: 0))
        #expect(decoder.systems[0][0].volume == 0)
    }

    @Test func eachChannelFeedsItsOwnSystem() {
        var decoder = CybermoveDecoder()
        decoder.apply(.noteOn(channel: 15, note: 2, velocity: 80))
        #expect(decoder.systems[1][0].z == 16)
        #expect(decoder.systems[0][0].z == 0)
    }

    @Test func otherChannelsAndMessagesAreIgnored() {
        var decoder = CybermoveDecoder()
        #expect(decoder.apply(.noteOn(channel: 3, note: 0, velocity: 100)).isEmpty)
        #expect(decoder.apply(.noteOff(channel: 14, note: 0, velocity: 100)).isEmpty)
        #expect(decoder.apply(.clock).isEmpty)
    }

    @Test func unchangedValueProducesNoChange() {
        var decoder = CybermoveDecoder()
        decoder.apply(.noteOn(channel: 14, note: 0, velocity: 90))
        #expect(decoder.apply(.noteOn(channel: 14, note: 0, velocity: 90)).isEmpty)
    }

    @Test func stopResetsEverythingLikeCMO() {
        var decoder = CybermoveDecoder()
        decoder.apply(.noteOn(channel: 14, note: 96, velocity: 100))
        decoder.apply(.noteOn(channel: 15, note: 3, velocity: 50))
        let update = decoder.apply(.stop)
        #expect(update.didReset)
        #expect(update.changes.count == 2)
        #expect(decoder.systems.allSatisfy { $0.allSatisfy { $0 == SignalState() } })
        // A second Stop changes nothing (Realtimer sends two).
        #expect(decoder.apply(.stop).changes.isEmpty)
    }

    @Test func channelMappingIsConfigurable() {
        var decoder = CybermoveDecoder(config: CybermoveConfig(channels: [3]))
        decoder.apply(.noteOn(channel: 3, note: 0, velocity: 70))
        #expect(decoder.systems[0][0].x == 6)
    }
}

// MARK: - The real thing: a capture from Realtimer playing in Hatari

@Suite struct RealtimerCaptureTests {
    private func capture() throws -> [UInt8] {
        let url = try #require(Bundle.module.url(forResource: "realtimer-play", withExtension: "bin",
                                                 subdirectory: "Fixtures"))
        return [UInt8](try Data(contentsOf: url))
    }

    @Test func captureDecodesCleanly() throws {
        let bytes = try capture()
        #expect(bytes.count == 26_690)

        var parser = MidiParser()
        let messages = parser.feed(bytes)
        let noteOns = messages.filter { if case .noteOn = $0 { true } else { false } }
        #expect(noteOns.count == 8_896)
        #expect(messages.filter { $0 == .stop }.count == 2)
        // Every byte belongs to a Note On or Stop: 8896 * 3 + 2 = 26690.
        #expect(messages.count == 8_898)
    }

    @Test func captureDrivesSignals24To31OnChannel15() throws {
        var parser = MidiParser()
        var decoder = CybermoveDecoder()
        var moved = Set<Int>()
        var sawReset = false

        for message in parser.feed(try capture()) {
            let update = decoder.apply(message)
            sawReset = sawReset || update.didReset
            if !update.didReset {
                for change in update.changes where change.system == 0 { moved.insert(change.signal) }
            }
        }
        #expect(moved == Set(24...31))
        #expect(sawReset)
        // The capture ends with Stop, so everything is back at zero.
        #expect(decoder.systems.allSatisfy { $0.allSatisfy { $0 == SignalState() } })
    }
}
