import CybermoveCore
import Darwin
import Foundation
import Synchronization
import Testing
@testable import HatariMidiBridgeKit

/// These tests use real FIFOs and the real CoreMIDI server, like Hatari and a
/// sequencer would.
@Suite(.serialized) struct BridgeTests {
    private struct Rig {
        let bridge: MidiBridge
        let outPath: String
        let inPath: String
        let hatariOut: Int32     // Hatari's --midi-out, as Hatari would open it (write)
        let hatariIn: Int32      // Hatari's --midi-in, as Hatari would open it (read)

        func hatariSends(_ bytes: [UInt8]) {
            _ = bytes.withUnsafeBytes { write(hatariOut, $0.baseAddress, $0.count) }
        }

        /// What Hatari has read from its input so far.
        func hatariReceives() -> [UInt8] {
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = read(hatariIn, &buffer, buffer.count)
            return count > 0 ? Array(buffer[0..<count]) : []
        }
    }

    private func makeRig(configure: (inout BridgeConfig) -> Void = { _ in },
                         log: (@Sendable (String) -> Void)? = nil) throws -> Rig {
        let id = UUID().uuidString
        var config = BridgeConfig(outFIFO: "/tmp/hmb-test-\(id).out", inFIFO: "/tmp/hmb-test-\(id).in")
        config.sourceName = "Bridge Test Out \(id)"
        config.destinationName = "Bridge Test In \(id)"
        configure(&config)
        let bridge = try MidiBridge(config: config, log: log)
        // The way Hatari opens them: --midi-out for writing, --midi-in for reading.
        let out = open(config.outFIFO, O_WRONLY | O_NONBLOCK)
        let input = open(config.inFIFO, O_RDONLY | O_NONBLOCK)
        #expect(out >= 0 && input >= 0)
        return Rig(bridge: bridge, outPath: config.outFIFO, inPath: config.inFIFO, hatariOut: out, hatariIn: input)
    }

    private func collect(_ stream: AsyncStream<[UInt8]>, count: Int, timeoutSeconds: Double = 5) async -> [UInt8] {
        let received = Mutex<[UInt8]>([])
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await chunk in stream {
                    let total = received.withLock { $0 += chunk; return $0.count }
                    if total >= count { return }
                }
            }
            group.addTask { try? await Task.sleep(for: .seconds(timeoutSeconds)) }
            await group.next()
            group.cancelAll()
        }
        return received.withLock { $0 }
    }

    private func finish(_ rig: Rig) {
        close(rig.hatariOut)
        close(rig.hatariIn)
        rig.bridge.stop()
        unlink(rig.outPath)
        unlink(rig.inPath)
    }

    // MARK: Hatari to Mac

    @Test func whatHatariWritesAppearsOnTheCoreMIDISource() async throws {
        let rig = try makeRig()
        defer { finish(rig) }
        let stream = CoreMIDIByteSource(sourceID: rig.bridge.sourceID).bytes()
        rig.hatariSends([0x9E, 0x60, 0x40, 0x9F, 0x01, 0x7F, 0xFC])
        let received = await collect(stream, count: 7)
        #expect(received == [0x9E, 0x60, 0x40, 0x9F, 0x01, 0x7F, 0xFC])
        #expect(rig.bridge.snapshot().bytesFromHatari == 7)
        #expect(rig.bridge.snapshot().messagesFromHatari == 3)
    }

    @Test func aMessageSplitBetweenTwoWritesIsStillOneMessage() async throws {
        let rig = try makeRig()
        defer { finish(rig) }
        let stream = CoreMIDIByteSource(sourceID: rig.bridge.sourceID).bytes()
        rig.hatariSends([0x9E, 0x60])
        try await Task.sleep(for: .milliseconds(100))
        rig.hatariSends([0x40])
        let received = await collect(stream, count: 3)
        #expect(received == [0x9E, 0x60, 0x40])
    }

    @Test func runningStatusFromTheAtariIsExpandedForCoreMIDI() async throws {
        let rig = try makeRig()
        defer { finish(rig) }
        let stream = CoreMIDIByteSource(sourceID: rig.bridge.sourceID).bytes()
        rig.hatariSends([0x90, 60, 100, 62, 101])
        let received = await collect(stream, count: 6)
        #expect(received == [0x90, 60, 100, 0x90, 62, 101])
    }

    @Test func sysexSurvivesTheTripInBothDirections() async throws {
        let rig = try makeRig()
        defer { finish(rig) }
        let sysex: [UInt8] = [0xF0, 0x7D, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 0xF7]
        let stream = CoreMIDIByteSource(sourceID: rig.bridge.sourceID).bytes()
        rig.hatariSends(sysex)
        #expect(await collect(stream, count: sysex.count) == sysex)

        let sender = try CoreMIDISender()
        #expect(sender.send(bytes: sysex, toDestinationID: rig.bridge.destinationID))
        try await Task.sleep(for: .milliseconds(300))
        #expect(rig.hatariReceives() == sysex)
    }

    @Test func theRealCaptureArrivesUnchanged() async throws {
        let url = try #require(Bundle.module.url(forResource: "realtimer-play", withExtension: "bin",
                                                 subdirectory: "Fixtures"))
        let capture = [UInt8](try Data(contentsOf: url))
        let rig = try makeRig()
        defer { finish(rig) }
        let stream = CoreMIDIByteSource(sourceID: rig.bridge.sourceID).bytes()
        let engine = MonitorEngine()
        let reader = Task { for await chunk in stream { engine.ingest(chunk) } }
        // Feed it like Hatari would, in pieces and not faster than the pipe takes it.
        let writer = Task.detached {
            var offset = 0
            while offset < capture.count {
                let piece = Array(capture[offset..<min(offset + 512, capture.count)])
                _ = piece.withUnsafeBytes { write(rig.hatariOut, $0.baseAddress, $0.count) }
                offset += piece.count
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
        for _ in 0..<200 {
            if engine.snapshot().bytesReceived >= capture.count { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        writer.cancel()
        reader.cancel()
        let snapshot = engine.snapshot()
        #expect(snapshot.bytesReceived == 26_690)
        #expect(snapshot.noteOnCount == 8_896)
        #expect(snapshot.stopCount == 2)
    }

    // MARK: Mac to Hatari

    @Test func whatAnAppSendsToTheDestinationReachesHatari() async throws {
        let rig = try makeRig()
        defer { finish(rig) }
        let sender = try CoreMIDISender()
        #expect(sender.send(bytes: [0xFA, 0xB0, 7, 100, 0xC1, 5, 0xFC], toDestinationID: rig.bridge.destinationID))
        try await Task.sleep(for: .milliseconds(300))
        #expect(rig.hatariReceives() == [0xFA, 0xB0, 7, 100, 0xC1, 5, 0xFC])
        #expect(rig.bridge.snapshot().bytesToHatari == 7)
    }

    @Test func clockAndSensingCanBeLeftOut() async throws {
        let rig = try makeRig { $0.dropClock = true; $0.dropActiveSensing = true }
        defer { finish(rig) }
        let stream = CoreMIDIByteSource(sourceID: rig.bridge.sourceID).bytes()
        let sender = try CoreMIDISender()
        sender.send(bytes: [0xF8, 0xFA, 0xFE, 0xF8], toDestinationID: rig.bridge.destinationID)
        rig.hatariSends([0xF8, 0xFC, 0xFE])
        try await Task.sleep(for: .milliseconds(300))
        #expect(rig.hatariReceives() == [0xFA])
        #expect(await collect(stream, count: 1) == [0xFC])
    }

    @Test func bytesAreDiscardedWhileHatariIsNotRunning() async throws {
        let notes = Mutex<[String]>([])
        let rig = try makeRig(log: { text in notes.withLock { $0.append(text) } })
        defer { finish(rig) }
        close(rig.hatariIn)                        // Hatari quits
        let sender = try CoreMIDISender()
        sender.send(bytes: [0xFA], toDestinationID: rig.bridge.destinationID)
        try await Task.sleep(for: .milliseconds(300))
        #expect(rig.bridge.snapshot().discardedNoReader == 1)
        #expect(rig.bridge.snapshot().bytesToHatari == 0)
        #expect(notes.withLock { $0 }.filter { $0.contains("not running") }.count == 1)

        // Nothing waits in the FIFO for the next Hatari.
        let again = open(rig.inPath, O_RDONLY | O_NONBLOCK)
        defer { close(again) }
        var byte: UInt8 = 0
        #expect(read(again, &byte, 1) < 0)         // EAGAIN: empty, not end of file

        // And when Hatari is back, bytes flow again.
        sender.send(bytes: [0xFC], toDestinationID: rig.bridge.destinationID)
        try await Task.sleep(for: .milliseconds(300))
        #expect(read(again, &byte, 1) == 1 && byte == 0xFC)
    }

    @Test func aStalledHatariFillsTheFIFOAndBytesAreDropped() async throws {
        let rig = try makeRig()
        defer { finish(rig) }
        let sender = try CoreMIDISender()
        // Hatari has the FIFO open but never reads it. A FIFO holds 64 KB at most.
        let chunk = [UInt8](repeating: 0xF8, count: 1000)       // 1000 clock bytes
        for _ in 0..<80 {
            sender.send(bytes: chunk, toDestinationID: rig.bridge.destinationID)
        }
        try await Task.sleep(for: .milliseconds(1000))
        let stats = rig.bridge.snapshot()
        #expect(stats.droppedFull > 0)
        #expect(stats.bytesToHatari > 0)
        // everything sent is either in the FIFO or counted as dropped (CoreMIDI may
        // still have a little in flight)
        #expect(stats.bytesToHatari + stats.droppedFull <= 80_000)
        #expect(stats.bytesToHatari + stats.droppedFull > 60_000)
    }

    // MARK: Setup

    @Test func hatariCanOpenTheFIFOsBlockingBeforeAnyoneIsListening() throws {
        // Hatari opens its files with a plain blocking open. Without the
        // bridge's ends already open, these would wait forever.
        let rig = try makeRig()
        defer { finish(rig) }
        let opened = DispatchSemaphore(value: 0)
        let results = Mutex<[Int32]>([])
        for (path, mode) in [(rig.inPath, O_RDONLY), (rig.outPath, O_WRONLY)] {
            DispatchQueue.global().async {
                let descriptor = open(path, mode)
                results.withLock { $0.append(descriptor) }
                opened.signal()
            }
        }
        #expect(opened.wait(timeout: .now() + 3) == .success)
        #expect(opened.wait(timeout: .now() + 3) == .success)
        for descriptor in results.withLock({ $0 }) { #expect(descriptor >= 0); close(descriptor) }
    }

    @Test func aRestartedBridgeKeepsTheSameFIFOs() throws {
        let rig = try makeRig()
        var inode = stat()
        stat(rig.outPath, &inode)
        let first = inode.st_ino
        rig.bridge.stop()
        let second = try MidiBridge(config: rig.bridge.config)
        stat(rig.outPath, &inode)
        #expect(inode.st_ino == first)
        second.stop()
        close(rig.hatariOut); close(rig.hatariIn)
        unlink(rig.outPath); unlink(rig.inPath)
    }

    @Test func aRegularFileInThePlaceOfAFIFOIsRefused() throws {
        let path = "/tmp/hmb-test-\(UUID().uuidString).txt"
        FileManager.default.createFile(atPath: path, contents: Data())
        defer { unlink(path) }
        #expect(throws: BridgeError.self) {
            _ = try MidiBridge(config: BridgeConfig(outFIFO: path, inFIFO: path + ".in"))
        }
    }

    @Test func theEndpointsAreListedUnderTheirNames() throws {
        let rig = try makeRig()
        defer { finish(rig) }
        #expect(CoreMIDIDevices.sources().contains { $0.name.contains(rig.bridge.config.sourceName) })
        #expect(CoreMIDIDevices.destinations().contains { $0.name.contains(rig.bridge.config.destinationName) })
    }
}
