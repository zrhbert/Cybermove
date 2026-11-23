import CoreGraphics
import Foundation

/// How CMO groups the 32 signals of a system into cubes (the "Grafikmodus"):
/// mono shows each signal in its own cube, okto packs eight signals into one.
public enum GraphicsMode: Int, CaseIterable, Sendable {
    case mono = 1, stereo = 2, quadro = 4, okto = 8

    public var signalsPerCube: Int { rawValue }
    public var cubeCount: Int { CybermoveDecoder.signalsPerSystem / rawValue }

    /// Grid of cubes in the window, as in CMO's `ComputeWorkDO`.
    public var rows: Int {
        switch self {
        case .mono, .stereo, .quadro: 4
        case .okto: 2
        }
    }

    public var columns: Int {
        switch self {
        case .mono: 8
        case .stereo: 4
        case .quadro, .okto: 2
        }
    }

    public var name: String {
        switch self {
        case .mono: "Mono"
        case .stereo: "Stereo"
        case .quadro: "Quadro"
        case .okto: "Okto"
        }
    }

    /// The signal numbers shown in cube `cube`.
    public func signals(inCube cube: Int) -> Range<Int> {
        (cube * signalsPerCube)..<((cube + 1) * signalsPerCube)
    }
}

/// The oblique projection of Realtimer's 3D displays (`Project3D` in
/// dispobj.c): depth shifts a point left and down (towards the viewer) or right
/// and up (away), by amounts set by the two rotation angles.
///
/// Realtimer's defaults are rotation 60 and 50 degrees with no perspective.
/// Coordinates here are -1 to +1 per axis; +z is towards the viewer.
public struct SpaceProjection: Sendable {
    public var rotationX: Double
    public var rotationY: Double
    /// Depth scaling, 0 means none. The Atari value is in its own units, so
    /// this is an approximation of its behaviour, not an exact port.
    public var perspective: Double

    public init(rotationX: Double = 60, rotationY: Double = 50, perspective: Double = 0) {
        self.rotationX = rotationX
        self.rotationY = rotationY
        self.perspective = perspective
    }

    /// The depth shift per unit of z. Realtimer computes `100 * sin(angle)` as an
    /// integer and divides by 128; this keeps that rounding.
    private var shiftX: Double { Double(Int(100 * sin(rotationX * .pi / 180))) / 128 }
    private var shiftY: Double { Double(Int(100 * sin(rotationY * .pi / 180))) / 128 }

    /// Projection onto the picture plane, x to the right and y up, unscaled.
    public func plane(x: Double, y: Double, z: Double) -> SIMD2<Double> {
        let scale = 1 + z * perspective / 100
        return SIMD2((x - z * shiftX) * scale, (y - z * shiftY) * scale)
    }

    /// The plane extent of the cube [-1, 1]^3, used to fit it into a view.
    public var cubeBounds: (min: SIMD2<Double>, max: SIMD2<Double>) {
        var lower = SIMD2<Double>(.infinity, .infinity)
        var upper = SIMD2<Double>(-.infinity, -.infinity)
        for x in [-1.0, 1.0] {
            for y in [-1.0, 1.0] {
                for z in [-1.0, 1.0] {
                    let point = plane(x: x, y: y, z: z)
                    lower = SIMD2(Swift.min(lower.x, point.x), Swift.min(lower.y, point.y))
                    upper = SIMD2(Swift.max(upper.x, point.x), Swift.max(upper.y, point.y))
                }
            }
        }
        return (lower, upper)
    }

    /// Position in `rect` (y down, as in UI coordinates), with the cube filling
    /// the rect minus `inset`, a fraction of its size on each side.
    public func screen(x: Double, y: Double, z: Double, in rect: CGRect, inset: Double = 0.08) -> CGPoint {
        let point = plane(x: x, y: y, z: z)
        let bounds = cubeBounds
        let width = rect.width * (1 - 2 * inset)
        let height = rect.height * (1 - 2 * inset)
        let u = (point.x - bounds.min.x) / (bounds.max.x - bounds.min.x)
        let v = (bounds.max.y - point.y) / (bounds.max.y - bounds.min.y)
        return CGPoint(x: rect.minX + rect.width * inset + u * width,
                       y: rect.minY + rect.height * inset + v * height)
    }
}

extension SignalState {
    /// Coordinates scaled to the -1...1 cube. The wire range is -64...63.
    public var unitPosition: (x: Double, y: Double, z: Double) {
        (Double(x) / 64, Double(y) / 64, Double(z) / 64)
    }

    /// Volume as 0...1.
    public var unitVolume: Double { Double(volume) / 127 }
}
