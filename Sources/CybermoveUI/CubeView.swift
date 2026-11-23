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
    let options: DisplayOptions

    public init(cube: Int, mode: GraphicsMode, signals: [SignalState], options: DisplayOptions = DisplayOptions()) {
        self.cube = cube
        self.mode = mode
        self.signals = signals
        self.options = options
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
            draw(into: &context, size: size)
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

    // MARK: - Drawing

    private func draw(into context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        let projection = options.projection
        let range = mode.signals(inCube: cube)
        let zoom = options.insideView ? 3.0 : 1.0

        // Where a signal's position lands in the cell. The inside view zooms in
        // on the middle third; points outside are held at the cell's edge.
        func screenPoint(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
            let point = projection.screen(x: x, y: y, z: z, in: rect)
            return CGPoint(x: min(max(point.x, rect.minX), rect.maxX),
                           y: min(max(point.y, rect.minY), rect.maxY))
        }
        func position(of index: Int) -> (x: Double, y: Double, z: Double) {
            let p = signals[index].unitPosition
            return (p.x * zoom, p.y * zoom, p.z * zoom)
        }

        // Cube outline.
        var outline = Path()
        let corners = Self.corners.map { projection.screen(x: $0.0, y: $0.1, z: $0.2, in: rect) }
        for (from, to) in Self.edges {
            outline.move(to: corners[from])
            outline.addLine(to: corners[to])
        }
        context.stroke(outline, with: .color(.primary.opacity(0.55)), lineWidth: 1)

        // Crosshairs: a line along each axis through every point.
        if options.showCrosshairs {
            for (offset, index) in range.enumerated() {
                let p = position(of: index)
                var cross = Path()
                cross.move(to: screenPoint(-1, p.y, p.z)); cross.addLine(to: screenPoint(1, p.y, p.z))
                cross.move(to: screenPoint(p.x, -1, p.z)); cross.addLine(to: screenPoint(p.x, 1, p.z))
                cross.move(to: screenPoint(p.x, p.y, -1)); cross.addLine(to: screenPoint(p.x, p.y, 1))
                context.stroke(cross, with: .color(Self.color(for: offset).opacity(0.55)),
                               style: StrokeStyle(lineWidth: 0.7, dash: [3, 2]))
            }
        }

        let points = range.map { index -> CGPoint in
            let p = position(of: index)
            return screenPoint(p.x, p.y, p.z)
        }

        // Lines joining the signals.
        if options.showLines {
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
            context.stroke(lines, with: .color(.primary), lineWidth: 1.2)
        }

        // Points, and their numbers.
        for (offset, index) in range.enumerated() {
            let signal = signals[index]
            let radius = options.dotSizeFollowsVolume ? 1.5 + 3 * signal.unitVolume : 3.5
            let dot = CGRect(x: points[offset].x - radius, y: points[offset].y - radius,
                             width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: dot), with: .color(Self.color(for: offset)))
            // Idle signals all sit at the centre; their numbers would pile up.
            if options.showSignalNumbers, signal != SignalState() {
                context.draw(Text("\(index)").font(.system(size: 9, design: .monospaced)),
                             at: CGPoint(x: points[offset].x + radius + 5, y: points[offset].y - radius - 3))
            }
        }

        // Volume bars along the bottom, one per signal, as in Realtimer.
        if options.showVolumeBars {
            let count = range.count
            let barHeight = max(2, min(5, size.height * 0.02))
            let maxWidth = size.width * 0.3
            for (offset, index) in range.enumerated() {
                let y = size.height - 4 - CGFloat(count - offset) * (barHeight + 1.5)
                let bar = CGRect(x: 6, y: y, width: max(1, maxWidth * signals[index].unitVolume), height: barHeight)
                context.fill(Path(bar), with: .color(Self.color(for: offset).opacity(0.9)))
            }
        }
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
    let options: DisplayOptions

    public init(mode: GraphicsMode, signals: [SignalState], options: DisplayOptions = DisplayOptions()) {
        self.mode = mode
        self.signals = signals
        self.options = options
    }

    public var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<mode.rows, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<mode.columns, id: \.self) { column in
                        CubeView(cube: row * mode.columns + column, mode: mode, signals: signals, options: options)
                    }
                }
            }
        }
    }
}
