import Testing
@testable import CybermoveCore

@Suite struct UMPTests {
    @Test func channelVoiceBytesRoundTrip() {
        // type 2, group 0, status 0x9E, note 0x60, velocity 0x40
        let words = UMP.words(for: .noteOn(channel: 14, note: 0x60, velocity: 0x40))
        #expect(words == [0x209E_6040])
        #expect(UMP.bytes(fromWords: words) == [0x9E, 0x60, 0x40])
    }

    @Test func oneByteVoiceMessagesAreTwoBytesOnTheWire() {
        #expect(UMP.bytes(fromWords: UMP.words(for: .programChange(channel: 3, program: 7))) == [0xC3, 7])
        #expect(UMP.bytes(fromWords: UMP.words(for: .channelPressure(channel: 1, pressure: 9))) == [0xD1, 9])
    }

    @Test func transportMessagesRoundTrip() {
        for (message, bytes) in [(MidiMessage.start, [UInt8]([0xFA])), (.continue, [0xFB]), (.stop, [0xFC]),
                                 (.clock, [0xF8]), (.songPosition(0x101), [0xF2, 0x01, 0x02]),
                                 (.quarterFrame(0x23), [0xF1, 0x23]), (.songSelect(5), [0xF3, 5])] {
            #expect(UMP.bytes(fromWords: UMP.words(for: message)) == bytes)
        }
    }

    @Test func shortSysexFitsOnePacket() {
        let words = UMP.words(for: .sysex([0x7F, 0x01, 0x06, 0x02]))
        #expect(words.count == 2)
        #expect(UMP.bytes(fromWords: words) == [0xF0, 0x7F, 0x01, 0x06, 0x02, 0xF7])
    }

    @Test func longSysexIsSplitAndReassembled() {
        let payload = (1...20).map { UInt8($0) }
        let words = UMP.words(for: .sysex(payload))
        #expect(words.count == 8)                      // four packets of two words
        #expect(UMP.bytes(fromWords: words) == [0xF0] + payload + [0xF7])
    }

    @Test func messagesSurviveTheFullRoundTrip() {
        let messages: [MidiMessage] = [
            .noteOn(channel: 15, note: 3, velocity: 0), .noteOff(channel: 0, note: 60, velocity: 64),
            .controlChange(channel: 2, controller: 20, value: 100), .pitchBend(channel: 1, value: 8192),
            .start, .stop, .sysex([1, 2, 3, 4, 5, 6, 7]), .polyPressure(channel: 4, note: 9, pressure: 77),
        ]
        var parser = MidiParser()
        let words = messages.flatMap { UMP.words(for: $0) }
        #expect(parser.feed(UMP.bytes(fromWords: words)) == messages)
    }

    @Test func truncatedAndUnknownPacketsAreSkipped() {
        // A sysex packet missing its second word is dropped; type 0 utility is skipped.
        #expect(UMP.bytes(fromWords: [0x3000_0000]) == [])
        #expect(UMP.bytes(fromWords: [0x0000_0000, 0x2090_3C40]) == [0x90, 0x3C, 0x40])
    }
}
