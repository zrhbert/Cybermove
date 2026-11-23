import CybermoveCore
import SwiftUI

/// The window content for one snapshot. Pure drawing, so it can also be
/// rendered to an image (see cybermove-snapshot).
public struct MonitorContent: View {
    let snapshot: MonitorSnapshot
    let mode: GraphicsMode
    let system: Int

    public init(snapshot: MonitorSnapshot, mode: GraphicsMode, system: Int) {
        self.snapshot = snapshot
        self.mode = mode
        self.system = system
    }

    public var body: some View {
        let signals = snapshot.systems.indices.contains(system)
            ? snapshot.systems[system]
            : Array(repeating: SignalState(), count: CybermoveDecoder.signalsPerSystem)
        HStack(alignment: .top, spacing: 12) {
            // Not in a ScrollView: 32 rows fit at this font size, and the window
            // has a minimum height. (ImageRenderer cannot draw scroll views.)
            SignalTableView(signals: signals)
                .padding(8)
                .frame(width: 250, alignment: .top)
            CubeGridView(mode: mode, signals: signals)
        }
        .padding(8)
    }
}

/// Status line text, e.g. "receiving  26690 bytes  8898 messages".
func statusText(_ snapshot: MonitorSnapshot, isRunning: Bool, now: Date) -> String {
    let state = !isRunning ? "stopped" : snapshot.isReceiving(at: now) ? "receiving" : "waiting for data"
    return "\(state)   \(snapshot.bytesReceived) bytes   \(snapshot.messagesReceived) messages   \(snapshot.stopCount) stops"
}

/// The live window: controls on top, the sampled state below.
public struct MonitorView: View {
    @Bindable var controller: MonitorController

    public init(controller: MonitorController) {
        self.controller = controller
    }

    public var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
                let snapshot = controller.engine.snapshot()
                VStack(spacing: 0) {
                    MonitorContent(snapshot: snapshot, mode: controller.mode, system: controller.selectedSystem)
                    Divider()
                    HStack {
                        Text(statusText(snapshot, isRunning: controller.isRunning, now: timeline.date))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(6)
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("Source", selection: $controller.source) {
                Text("Hatari FIFO").tag(SourceChoice.fifo)
                Text("All MIDI inputs").tag(SourceChoice.allMIDIInputs)
                if !controller.offeredMIDISources.isEmpty {
                    Divider()
                    ForEach(controller.offeredMIDISources) { endpoint in
                        Text(endpoint.name).tag(SourceChoice.midi(id: endpoint.id))
                    }
                }
            }
            .frame(width: 280)
            if controller.source == .fifo {
                TextField("FIFO path", text: $controller.fifoPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 160)
                    .disabled(controller.isRunning)
            }
            Button(controller.isRunning ? "Stop" : "Start") {
                if controller.isRunning { controller.stop() } else { controller.start() }
            }
            Picker("System", selection: $controller.selectedSystem) {
                ForEach(controller.channels.indices, id: \.self) { index in
                    Text("Channel \(controller.channels[index] + 1)").tag(index)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            Picker("Mode", selection: $controller.mode) {
                ForEach(GraphicsMode.allCases, id: \.self) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            if let message = controller.errorMessage {
                Text(message).foregroundStyle(.red).font(.caption)
            }
        }
        .padding(8)
        .task {
            // Interfaces come and go; keep the list of inputs current.
            while !Task.isCancelled {
                controller.refreshMIDISources()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
