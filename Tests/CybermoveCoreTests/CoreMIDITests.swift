import Foundation
import Synchronization
import Testing
@testable import CybermoveCore

/// These tests talk to the real CoreMIDI server through a virtual source, so
/// they need no hardware but do need a normal macOS session.
@Suite(.serialized) struct CoreMIDITests {
    private func makeSource() throws -> CoreMIDIVirtualSource {
        try CoreMIDIVirtualSource(name: "Cybermove Test \(UUID().uuidString)")
    }

    private func collect(_ stream: AsyncStream<[UInt8]>, count: Int, timeoutSeconds: Double) async -> [UInt8] {
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

    @Test func virtualSourceIsListedWithItsName() throws {
        let source = try makeSource()
        let listed = CoreMIDIDevices.sources()
        #expect(listed.contains { $0.id == source.uniqueID })
    }

    @Test func bytesArriveThroughAVirtualSource() async throws {
        let source = try makeSource()
        let stream = CoreMIDIByteSource(sourceID: source.uniqueID).bytes()   // connected on creation
        source.send(bytes: [0x9E, 0x60, 0x40, 0x9F, 0x01, 0x7F, 0xFC])
        let received = await collect(stream, count: 7, timeoutSeconds: 5)
        #expect(received == [0x9E, 0x60, 0x40, 0x9F, 0x01, 0x7F, 0xFC])
    }

    @Test func otherSourcesAreNotHeardWhenOneIsSelected() async throws {
        let wanted = try makeSource()
        let other = try makeSource()
        let stream = CoreMIDIByteSource(sourceID: wanted.uniqueID).bytes()
        other.send(bytes: [0x90, 1, 1])
        wanted.send(bytes: [0x90, 2, 2])
        let received = await collect(stream, count: 3, timeoutSeconds: 5)
        #expect(received == [0x90, 2, 2])
    }

    @Test func theRealCaptureSurvivesTheTripThroughCoreMIDI() async throws {
        let url = try #require(Bundle.module.url(forResource: "realtimer-play", withExtension: "bin",
                                                 subdirectory: "Fixtures"))
        let capture = [UInt8](try Data(contentsOf: url))
        let source = try makeSource()
        let stream = CoreMIDIByteSource(sourceID: source.uniqueID).bytes()
        let engine = MonitorEngine()
        let reader = Task { for await chunk in stream { engine.ingest(chunk) } }

        source.send(bytes: capture)
        for _ in 0..<100 {
            if engine.snapshot().bytesReceived >= capture.count { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        reader.cancel()

        let snapshot = engine.snapshot()
        #expect(snapshot.bytesReceived == 26_690)
        #expect(snapshot.noteOnCount == 8_896)
        #expect(snapshot.stopCount == 2)
    }
}
