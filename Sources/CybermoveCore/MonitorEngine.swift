import Foundation
import Synchronization

/// What the user interface needs to draw one frame.
public struct MonitorSnapshot: Sendable {
    public var channels: [UInt8]
    public var systems: [[SignalState]]
    public var bytesReceived = 0
    public var messagesReceived = 0
    public var noteOnCount = 0
    public var stopCount = 0
    /// When the most recent byte arrived, nil if none yet.
    public var lastByteTime: Date?

    /// True while data keeps arriving.
    public func isReceiving(at now: Date = .now, within seconds: TimeInterval = 1) -> Bool {
        guard let lastByteTime else { return false }
        return now.timeIntervalSince(lastByteTime) < seconds
    }
}

/// Feeds bytes through the parser and the decoder and hands out consistent
/// snapshots. Thread safe: bytes arrive on a reader thread while the user
/// interface takes snapshots on the main thread at its own pace. The UI does
/// not observe individual changes; the change handler tells it that new data
/// is there, and it takes one snapshot per frame however many messages came.
public final class MonitorEngine: Sendable {
    private struct State {
        var parser = MidiParser()
        var decoder: CybermoveDecoder
        var bytes = 0
        var messages = 0
        var noteOns = 0
        var stops = 0
        var lastByteTime: Date?
    }

    /// Holds the handler in a class. Reading a closure back out of a generic
    /// `Mutex` wraps it in another reabstraction thunk, so every change added
    /// a level to the call stack until it overflowed.
    private final class ChangeHandler: Sendable {
        let call: @Sendable () -> Void

        init(_ call: @escaping @Sendable () -> Void) {
            self.call = call
        }
    }

    private let state: Mutex<State>
    private let changeHandler = Mutex<ChangeHandler?>(nil)

    public init(config: CybermoveConfig = CybermoveConfig()) {
        state = Mutex(State(decoder: CybermoveDecoder(config: config)))
    }

    /// Called, on whatever thread caused it, after the state changed: bytes
    /// arrived, or the engine was reset or reconfigured. The handler should be
    /// quick and must not call back into the engine under a lock.
    public func setChangeHandler(_ handler: (@Sendable () -> Void)?) {
        changeHandler.withLock { $0 = handler.map(ChangeHandler.init) }
    }

    private func notifyChange() {
        changeHandler.withLock { $0 }?.call()
    }

    /// Process a chunk of raw bytes.
    public func ingest(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        let now = Date.now
        state.withLock { state in
            state.bytes += bytes.count
            state.lastByteTime = now
            for message in state.parser.feed(bytes) {
                state.messages += 1
                switch message {
                case .noteOn: state.noteOns += 1
                case .stop: state.stops += 1
                default: break
                }
                state.decoder.apply(message)
            }
        }
        notifyChange()
    }

    /// Consume a byte source until it ends or the surrounding task is cancelled.
    public func run(_ source: some MidiByteSource) async {
        for await chunk in source.bytes() {
            if Task.isCancelled { return }
            ingest(chunk)
        }
    }

    public func snapshot() -> MonitorSnapshot {
        state.withLock { state in
            MonitorSnapshot(
                channels: state.decoder.config.channels,
                systems: state.decoder.systems,
                bytesReceived: state.bytes,
                messagesReceived: state.messages,
                noteOnCount: state.noteOns,
                stopCount: state.stops,
                lastByteTime: state.lastByteTime
            )
        }
    }

    /// Change which MIDI channels feed the systems. Clears all signals.
    public func setChannels(_ channels: [UInt8]) {
        state.withLock { state in
            state.decoder = CybermoveDecoder(config: CybermoveConfig(channels: channels))
            state.parser = MidiParser()
        }
        notifyChange()
    }

    /// Clear signals, counters and parser state.
    public func reset() {
        state.withLock { state in
            let config = state.decoder.config
            state = State(decoder: CybermoveDecoder(config: config))
        }
        notifyChange()
    }
}
