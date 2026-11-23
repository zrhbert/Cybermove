import CybermoveCore
import SwiftUI

/// One cube with the signals it shows, drawn the way Realtimer's CMO does:
/// the oblique cube outline, and the signals joined according to the graphics
/// mode (mono: a line from the centre to the point; stereo: a line between
/// each pair; quadro and okto: an open line through all points).
public struct CubeView: View {
    let cube: Int
    let mode: GraphicsMode
    let signals: [SignalState]          // all 32 signals of the system
    let projection: SpaceProjection

    public init(cube: Int, mode: GraphicsMode, signals: [SignalState],
                projection: SpaceProjection = SpaceProjection()) {
        self.cube = cube
        self.mode = mode
        self.signals = signals
        self.projection = projection
    }

    private static let corners: [(Double, Double, Double)] = [
        (-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1),     // bottom
        (-1, 1, -1), (1, 1, -1), (1, 1, 1), (-1, 1, 1),         // top
    ]
    private static let edges: [(Int, Int)] = [
        (0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6), (6, 7), (7, 4), (0, 4), (1, 5), (2, 6), (3, 7),
    ]

    public var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let ink = GraphicsContext.Shading.color(.primary)

            // Cube outline.
            var outline = Path()
            let corners = Self.corners.map { projection.screen(x: $0.0, y: $0.1, z: $0.2, in: rect) }
            for (from, to) in Self.edges {
                outline.move(to: corners[from])
                outline.addLine(to: corners[to])
            }
            context.stroke(outline, with: .color(.primary.opacity(0.55)), lineWidth: 1)

            // Signals.
            let range = mode.signals(inCube: cube)
            let points: [CGPoint] = range.map { index in
                let position = signals[index].unitPosition
                return projection.screen(x: position.x, y: position.y, z: position.z, in: rect)
            }
            let centre = projection.screen(x: 0, y: 0, z: 0, in: rect)

            var lines = Path()
            switch mode {
            case .mono:
                for point in points {
                    lines.move(to: centre)
                    lines.addLine(to: point)
                }
            case .stereo:
                for pair in stride(from: 0, to: points.count - 1, by: 2) {
                    lines.move(to: points[pair])
                    lines.addLine(to: points[pair + 1])
                }
            case .quadro, .okto:
                lines.addLines(points)
            }
            context.stroke(lines, with: ink, lineWidth: 1.2)

            for (offset, index) in range.enumerated() {
                let signal = signals[index]
                let radius = 1.5 + 3 * signal.unitVolume
                let dot = CGRect(x: points[offset].x - radius, y: points[offset].y - radius,
                                 width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: dot), with: .color(Self.color(for: offset)))
            }
        }
        .overlay(alignment: .topLeading) {
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(2)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .border(Color.secondary.opacity(0.4), width: 0.5)
    }

    private var label: String {
        let range = mode.signals(inCube: cube)
        return range.count == 1 ? "\(range.lowerBound)" : "\(range.lowerBound)-\(range.upperBound - 1)"
    }

    private static func color(for offset: Int) -> Color {
        Color(hue: Double(offset % 8) / 8, saturation: 0.75, brightness: 0.85)
    }
}

/// The grid of cubes, laid out like CMO's window.
public struct CubeGridView: View {
    let mode: GraphicsMode
    let signals: [SignalState]

    public init(mode: GraphicsMode, signals: [SignalState]) {
        self.mode = mode
        self.signals = signals
    }

    public var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<mode.rows, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<mode.columns, id: \.self) { column in
                        CubeView(cube: row * mode.columns + column, mode: mode, signals: signals)
                    }
                }
            }
        }
    }
}
