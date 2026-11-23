import CybermoveCore
import SwiftUI

/// The numbers: one row per signal with X, Y, Z and volume, like Realtimer's
/// coordinate window. Rows without any data are dimmed.
public struct SignalTableView: View {
    let signals: [SignalState]

    public init(signals: [SignalState]) {
        self.signals = signals
    }

    public var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 1) {
            GridRow {
                Text("Sig").gridColumnAlignment(.leading)
                Text("X")
                Text("Y")
                Text("Z")
                Text("Vol")
                Text("").gridColumnAlignment(.leading)
            }
            .foregroundStyle(.secondary)
            Divider().gridCellColumns(6)
            ForEach(signals.indices, id: \.self) { index in
                let signal = signals[index]
                GridRow {
                    Text("\(index)").gridColumnAlignment(.leading)
                    Text("\(signal.x)")
                    Text("\(signal.y)")
                    Text("\(signal.z)")
                    Text("\(signal.volume)")
                    VolumeBar(value: signal.unitVolume)
                }
                .foregroundStyle(signal == SignalState() ? .tertiary : .primary)
            }
        }
        .font(.system(.caption, design: .monospaced))
        .monospacedDigit()
    }
}

private struct VolumeBar: View {
    let value: Double

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(.quaternary)
            Rectangle().fill(.tint).frame(width: 40 * value)
        }
        .frame(width: 40, height: 6)
    }
}
