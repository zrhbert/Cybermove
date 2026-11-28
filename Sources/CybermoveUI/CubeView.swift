import CybermoveCore
import SwiftUI

/// One cube with the signals it shows, seen through the shared camera. The
/// signals are joined according to the graphics mode as in Realtimer's CMO
/// (mono: a line from the centre to the point; stereo: a line between each
/// pair; quadro and okto: an open line through all points).
public struct CubeView: View {
    let cube: Int
    let mode: GraphicsMode
    let signals: [SignalState]          // all 32 signals of the system
    let options: DisplayOptions
    let firstNumber: Int

    public init(cube: Int, mode: GraphicsMode, signals: [SignalState], options: DisplayOptions = DisplayOptions(),
                firstNumber: Int = 0) {
        self.cube = cube
        self.mode = mode
        self.signals = signals
        self.options = options
        self.firstNumber = firstNumber
    }

    private typealias Vec = SIMD3<Double>

    private static let corners: [Vec] = [
        Vec(-1, -1, -1), Vec(1, -1, -1), Vec(1, -1, 1), Vec(-1, -1, 1),     // bottom
        Vec(-1, 1, -1), Vec(1, 1, -1), Vec(1, 1, 1), Vec(-1, 1, 1),         // top
    ]
    private static let edges: [(Int, Int)] = [
        (0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6), (6, 7), (7, 4), (0, 4), (1, 5), (2, 6), (3, 7),
    ]

    /// The six squares of side 2t centred on the faces of the cube, as in
    /// Realtimer's `wuerfel_innen`.
    static func innerSquares(_ t: Double) -> [[SIMD3<Double>]] {
        let m = -t
        return [
            [Vec(m, -1, m), Vec(t, -1, m), Vec(t, -1, t), Vec(m, -1, t)],      // bottom
            [Vec(m, 1, m), Vec(t, 1, m), Vec(t, 1, t), Vec(m, 1, t)],          // top
            [Vec(-1, m, m), Vec(-1, t, m), Vec(-1, t, t), Vec(-1, m, t)],      // left
            [Vec(1, m, m), Vec(1, t, m), Vec(1, t, t), Vec(1, m, t)],          // right
            [Vec(m, m, -1), Vec(t, m, -1), Vec(t, t, -1), Vec(m, t, -1)],      // back
            [Vec(m, m, 1), Vec(t, m, 1), Vec(t, t, 1), Vec(m, t, 1)],          // front
        ]
    }

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
        let camera = options.camera.resolved
        let range = mode.signals(inCube: cube)
        // The inside view frames the middle third of the cube; whatever lies
        // outside is cut off by the cell.
        let halfSize = options.insideView ? 1.0 / 3 : 1.0
        if options.insideView { context.clip(to: Path(rect)) }

        func screen(_ point: ProjectedPoint) -> CGPoint { camera.screen(point, in: rect) }
        /// A path through `points` in the model, cut where it passes behind the camera.
        func line(_ points: [Vec], closed: Bool = false, into path: inout Path) {
            let pairs = zip(points, points.dropFirst() + (closed ? [points[0]] : []))
            for (a, b) in pairs {
                guard let (pa, pb) = camera.project(from: a, to: b, halfSize: halfSize) else { continue }
                path.move(to: screen(pa))
                path.addLine(to: screen(pb))
            }
        }
        func position(of index: Int) -> Vec { signals[index].unitPosition }

        // Nearer edges are drawn stronger than the far ones.
        func shade(_ depth: Double) -> Double {
            guard options.depthCues else { return 1 }
            return 1 - 0.55 * min(max((depth / 3.0.squareRoot() + 1) / 2, 0), 1)
        }

        // Cube outline.
        for (from, to) in Self.edges {
            guard let (a, b) = camera.project(from: Self.corners[from], to: Self.corners[to], halfSize: halfSize)
            else { continue }
            var edge = Path()
            edge.move(to: screen(a))
            edge.addLine(to: screen(b))
            context.stroke(edge, with: .color(.primary.opacity(0.7 * shade((a.depth + b.depth) / 2))), lineWidth: 1)
        }

        // The inside area, marked by a dotted square on each face (not in the
        // inside view itself, where the whole cube is that area).
        if options.markInsideArea && !options.insideView {
            var squares = Path()
            for face in Self.innerSquares(1.0 / 3) { line(face, closed: true, into: &squares) }
            context.stroke(squares, with: .color(.primary.opacity(0.6)),
                           style: StrokeStyle(lineWidth: 1, dash: [1.5, 2.5]))
        }

        // Crosshairs: a line along each axis through every point.
        if options.showCrosshairs {
            for (offset, index) in range.enumerated() {
                let p = position(of: index)
                var cross = Path()
                line([Vec(-1, p.y, p.z), Vec(1, p.y, p.z)], into: &cross)
                line([Vec(p.x, -1, p.z), Vec(p.x, 1, p.z)], into: &cross)
                line([Vec(p.x, p.y, -1), Vec(p.x, p.y, 1)], into: &cross)
                context.stroke(cross, with: .color(Self.color(for: offset).opacity(0.55)),
                               style: StrokeStyle(lineWidth: 0.7, dash: [3, 2]))
            }
        }

        // The signals that are in front of the camera.
        let projected = range.map { camera.project(position(of: $0), halfSize: halfSize) }

        // Lines joining the signals.
        if options.showLines {
            var lines = Path()
            switch mode {
            case .mono:
                for index in range { line([.zero, position(of: index)], into: &lines) }
            case .stereo:
                for pair in stride(from: range.lowerBound, to: range.upperBound - 1, by: 2) {
                    line([position(of: pair), position(of: pair + 1)], into: &lines)
                }
            case .quadro, .okto:
                line(range.map(position(of:)), into: &lines)
            }
            context.stroke(lines, with: .color(.primary), lineWidth: 1.2)
        }

        // Points, farthest first so that nearer ones cover them, and their numbers.
        let order = (0..<range.count).sorted { (projected[$0]?.depth ?? 0) > (projected[$1]?.depth ?? 0) }
        for offset in order {
            guard let point = projected[offset] else { continue }
            let index = range.lowerBound + offset
            let signal = signals[index]
            let base = options.dotSizeFollowsVolume ? 1.5 + 3 * signal.unitVolume : 3.5
            let radius = base * (options.depthCues ? min(max(point.scale, 0.4), 2.5) : 1)
            let centre = screen(point)
            let dot = CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: dot), with: .color(Self.color(for: offset)))
            // Idle signals all sit at the centre; their numbers would pile up.
            if options.showSignalNumbers, signal != SignalState() {
                context.draw(Text("\(firstNumber + index)").font(.system(size: 9, design: .monospaced)),
                             at: CGPoint(x: centre.x + radius + 5, y: centre.y - radius - 3))
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
        let first = firstNumber + range.lowerBound
        let last = firstNumber + range.upperBound - 1
        return range.count == 1 ? "\(first)" : "\(first)-\(last)"
    }

    private static func color(for offset: Int) -> Color {
        Color(hue: Double(offset % 8) / 8, saturation: 0.75, brightness: 0.85)
    }
}

/// A small X, Y, Z indicator that turns with the camera.
struct AxesView: View {
    let camera: Camera

    var body: some View {
        Canvas { context, size in
            let view = Camera(yaw: camera.yaw, pitch: camera.pitch, roll: camera.roll, fieldOfView: 0, zoom: 1)
            let rect = CGRect(origin: .zero, size: size)
            let axes: [(String, SIMD3<Double>, Color)] = [
                ("X", SIMD3(1, 0, 0), .red), ("Y", SIMD3(0, 1, 0), .green), ("Z", SIMD3(0, 0, 1), .blue),
            ]
            let centre = view.screen(view.project(.zero)!, in: rect, inset: 0.2)
            // Farthest axis first.
            let tips = axes.map { (axis: $0, point: view.project($0.1, halfSize: 1 / 3.0.squareRoot())!) }
                .sorted { $0.point.depth > $1.point.depth }
            for (axis, point) in tips {
                let tip = view.screen(point, in: rect, inset: 0.2)
                var path = Path()
                path.move(to: centre)
                path.addLine(to: tip)
                context.stroke(path, with: .color(axis.2), lineWidth: 1.5)
                context.draw(Text(axis.0).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(axis.2),
                             at: CGPoint(x: tip.x + (tip.x - centre.x) * 0.3, y: tip.y + (tip.y - centre.y) * 0.3))
            }
        }
        .frame(width: 44, height: 44)
        .allowsHitTesting(false)
    }
}

/// The grid of cubes, laid out like CMO's window. With `onCameraChange` the
/// cubes can be turned, zoomed and re-lensed with the mouse and trackpad (see
/// `CameraInteraction`).
public struct CubeGridView: View {
    let mode: GraphicsMode
    let signals: [SignalState]
    let options: DisplayOptions
    let onCameraChange: ((Camera) -> Void)?
    let firstNumber: Int

    public init(mode: GraphicsMode, signals: [SignalState], options: DisplayOptions = DisplayOptions(),
                onCameraChange: ((Camera) -> Void)? = nil, firstNumber: Int = 0) {
        self.mode = mode
        self.signals = signals
        self.options = options
        self.onCameraChange = onCameraChange
        self.firstNumber = firstNumber
    }

    public var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<mode.rows, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<mode.columns, id: \.self) { column in
                        CubeView(cube: row * mode.columns + column, mode: mode, signals: signals, options: options,
                                 firstNumber: firstNumber)
                    }
                }
            }
        }
        .overlay(alignment: .topLeading) {
            // In the first cube, below its label.
            if options.showAxes { AxesView(camera: options.camera).padding(.top, 14).padding(.leading, 4) }
        }
        .overlay {
            // Not when rendering to an image, which cannot draw views from AppKit.
            if let onCameraChange { CameraInteraction(camera: options.camera, onChange: onCameraChange) }
        }
    }
}
