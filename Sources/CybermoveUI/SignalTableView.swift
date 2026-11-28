import CybermoveCore
import SwiftUI

/// The numbers: one row per signal with X, Y, Z and volume, like Realtimer's
/// coordinate window. Rows without any data are dimmed.
public struct SignalTableView: View {
    let signals: [SignalState]
    let firstNumber: Int

    public init(signals: [SignalState], firstNumber: Int = 0) {
        self.signals = signals
        self.firstNumber = firstNumber
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
                    Text("\(firstNumber + index)").gridColumnAlignment(.leading)
                    Text(Self.signed(signal.x))
                    Text(Self.signed(signal.y))
                    Text(Self.signed(signal.z))
                    Text("\(signal.volume)")
                    VolumeBar(value: signal.unitVolume)
                }
                .foregroundStyle(signal == SignalState() ? .tertiary : .primary)
            }
        }
        .font(.system(.caption, design: .monospaced))
        .monospacedDigit()
    }

    /// Always a sign and three digits, so the values line up: +063, -064.
    private static func signed(_ value: Int8) -> String {
        String(format: "%+04d", Int(value))
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
