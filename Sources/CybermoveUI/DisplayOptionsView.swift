import CybermoveCore
import SwiftUI

/// The display settings. Dragging in the cube area changes the same camera.
public struct DisplayOptionsView: View {
    @Binding var options: DisplayOptions

    public init(options: Binding<DisplayOptions>) {
        _options = options
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("View").font(.headline)
                Spacer()
                Menu("Presets") {
                    ForEach(Camera.presets.indices, id: \.self) { index in
                        Button(Camera.presets[index].name) { options.camera = Camera.presets[index].camera }
                    }
                }
                .fixedSize()
            }
            Text("Drag in the cubes to turn them, pinch to zoom, double-click to reset.")
                .font(.caption).foregroundStyle(.secondary)
            slider("Yaw", value: $options.camera.yaw, range: -180...180, unit: "°")
            slider("Pitch", value: $options.camera.pitch, range: -180...180, unit: "°")
            slider("Roll", value: $options.camera.roll, range: -180...180, unit: "°")
            slider("Perspective (field of view)", value: $options.camera.fieldOfView,
                   range: Camera.fieldOfViewRange, unit: "°", zeroLabel: "off")
            slider("Zoom", value: $options.camera.zoom, range: Camera.zoomRange, unit: "×", step: 0.05, decimals: 2)
            Toggle("Keep the whole cube in view", isOn: $options.camera.fitToView)
            Toggle("Inside view (zoom to the middle third)", isOn: $options.insideView)
            Toggle("Mark the inside area with dotted squares", isOn: $options.markInsideArea)
                .disabled(options.insideView)

            Divider()
            Text("Show").font(.headline)
            Toggle("Lines between signals", isOn: $options.showLines)
            Toggle("Crosshairs", isOn: $options.showCrosshairs)
            Toggle("Volume bars", isOn: $options.showVolumeBars)
            Toggle("Signal numbers", isOn: $options.showSignalNumbers)
            Toggle("Dot size follows volume", isOn: $options.dotSizeFollowsVolume)
            Toggle("Nearer is larger and stronger", isOn: $options.depthCues)
            Toggle("Axes indicator", isOn: $options.showAxes)

            Divider()
            Button("Reset") { options = DisplayOptions() }
                .disabled(options == DisplayOptions())
        }
        .padding(14)
        .frame(width: 320)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String,
                        step: Double = 1, decimals: Int = 0, zeroLabel: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                let shown = value.wrappedValue
                Text(zeroLabel != nil && shown < 1 ? zeroLabel! : String(format: "%.\(decimals)f", shown) + unit)
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            // No `step:` on the Slider: it gives the NSSlider a tick mark for every
            // step (361 for the angles), and laying those out took about a
            // second every time the popover opened. Snap the value instead.
            Slider(value: Binding(get: { value.wrappedValue },
                                  set: { value.wrappedValue = ($0 / step).rounded() * step }),
                   in: range)
        }
    }
}
