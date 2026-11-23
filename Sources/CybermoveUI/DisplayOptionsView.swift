import CybermoveCore
import SwiftUI

/// The display settings, named after Realtimer's A3D setup dialog where there
/// is a counterpart.
public struct DisplayOptionsView: View {
    @Binding var options: DisplayOptions

    public init(options: Binding<DisplayOptions>) {
        _options = options
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Perspective").font(.headline)
            slider("LR rotation", value: $options.rotationX, range: DisplayOptions.rotationRange, unit: "°")
            slider("OU rotation", value: $options.rotationY, range: DisplayOptions.rotationRange, unit: "°")
            slider("Depth effect", value: $options.perspective, range: DisplayOptions.perspectiveRange, unit: "")
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

            Divider()
            Button("Reset to Realtimer's defaults") { options = DisplayOptions() }
                .disabled(options == DisplayOptions())
        }
        .padding(14)
        .frame(width: 300)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue))\(unit)").monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 1)
        }
    }
}
