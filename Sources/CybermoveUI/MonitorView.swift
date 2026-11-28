import CybermoveCore
import SwiftUI

/// The window content for one snapshot. Pure drawing, so it can also be
/// rendered to an image (see cybermove-snapshot).
public struct MonitorContent: View {
    let snapshot: MonitorSnapshot
    let mode: GraphicsMode
    let system: Int
    let options: DisplayOptions
    let onCameraChange: ((Camera) -> Void)?

    public init(snapshot: MonitorSnapshot, mode: GraphicsMode, system: Int, options: DisplayOptions = DisplayOptions(),
                onCameraChange: ((Camera) -> Void)? = nil) {
        self.snapshot = snapshot
        self.mode = mode
        self.system = system
        self.options = options
        self.onCameraChange = onCameraChange
    }

    public var body: some View {
        let signals = snapshot.systems.indices.contains(system)
            ? snapshot.systems[system]
            : Array(repeating: SignalState(), count: CybermoveDecoder.signalsPerSystem)
        // Realtimer counts the signals of channel 15 as 32 to 63; system 0 is channel 15.
        let firstNumber = system == 0 ? CybermoveDecoder.signalsPerSystem : 0
        HStack(alignment: .top, spacing: 12) {
            // Not in a ScrollView: 32 rows fit at this font size, and the window
            // has a minimum height. (ImageRenderer cannot draw scroll views.)
            SignalTableView(signals: signals, firstNumber: firstNumber)
                .padding(8)
                .frame(width: 250, alignment: .top)
            CubeGridView(mode: mode, signals: signals, options: options, onCameraChange: onCameraChange,
                         firstNumber: firstNumber)
        }
        .padding(8)
    }
}

/// Status line text, e.g. "receiving  26690 bytes  8898 messages".
func statusText(_ snapshot: MonitorSnapshot, isRunning: Bool, isReceiving: Bool) -> String {
    let state = !isRunning ? "stopped" : isReceiving ? "receiving" : "waiting for data"
    return "\(state)   \(snapshot.bytesReceived) bytes   \(snapshot.messagesReceived) messages   \(snapshot.stopCount) stops"
}

/// The signals and the status line. A view of its own so that only this part
/// is evaluated when data arrives or the display settings change.
struct MonitorDisplay: View {
    let controller: MonitorController

    var body: some View {
        VStack(spacing: 0) {
            MonitorContent(snapshot: controller.snapshot, mode: controller.mode, system: controller.selectedSystem,
                           options: controller.options,
                           onCameraChange: { controller.options.camera = $0 })
            Divider()
            HStack {
                Text(statusText(controller.snapshot, isRunning: controller.isRunning,
                                isReceiving: controller.isReceiving))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(6)
        }
    }
}

/// The live window: controls on top, the state below.
public struct MonitorView: View {
    @Bindable var controller: MonitorController
    @State private var showingDisplayOptions = false

    public init(controller: MonitorController) {
        self.controller = controller
    }

    public var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            MonitorDisplay(controller: controller)
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
            Button {
                showingDisplayOptions.toggle()
            } label: {
                Label("Display", systemImage: "slider.horizontal.3")
            }
            .popover(isPresented: $showingDisplayOptions, arrowEdge: .bottom) {
                DisplayOptionsView(options: $controller.options)
            }
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
