import CoreGraphics
import Foundation
import simd

/// A point after projection.
public struct ProjectedPoint: Equatable, Sendable {
    /// Position in the view, x to the right and y up. The sphere around the
    /// model fits the unit circle (times the camera's zoom).
    public var x: Double
    public var y: Double
    /// How large things at this depth appear compared with the model's centre:
    /// above 1 is nearer than the centre, below 1 is farther. Always 1 without
    /// perspective.
    public var scale: Double
    /// Offset from the model's centre plane along the view axis, in model
    /// units: negative is nearer the camera, positive farther away.
    public var depth: Double
}

/// An orbit camera looking at the centre of the cube, with a real perspective
/// projection.
///
/// The cube is turned by `yaw` (about the vertical axis), then `pitch` (about
/// the horizontal axis) and `roll` (about the view axis), each over the full
/// 360 degrees. The camera sits on the view axis, `+z` pointing at the viewer,
/// and looks at the origin.
///
/// `fieldOfView` is the vertical opening angle of the lens. The camera's
/// distance is derived from it so that the sphere around the model always
/// fills the view the same way (a "dolly zoom"): changing the field of view
/// changes only the strength of the perspective, not the size of the picture.
/// A field of view below one degree means an orthographic projection with no
/// perspective at all.
///
/// With `fitToView` on, the picture is scaled so that the whole cube, seen
/// from the current direction, just fills the view, and `zoom` is relative to
/// that (1 is a snug fit, for the whole cube and, in the inside view, for the
/// inside area, so switching between the two keeps the size). With it off, `zoom` 1 is a fixed size that keeps
/// the cube inside the view from every direction, but a cube seen face-on
/// then fills only about 60% of it.
public struct Camera: Equatable, Codable, Sendable {
    public var yaw: Double
    public var pitch: Double
    public var roll: Double
    public var fieldOfView: Double
    public var zoom: Double
    public var fitToView: Bool

    public static let fieldOfViewRange: ClosedRange<Double> = 0...100
    public static let zoomRange: ClosedRange<Double> = 0.3...4

    public init(yaw: Double = -30, pitch: Double = 20, roll: Double = 0,
                fieldOfView: Double = 30, zoom: Double = 1, fitToView: Bool = true) {
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
        self.fieldOfView = fieldOfView
        self.zoom = zoom
        self.fitToView = fitToView
    }

    /// Missing keys keep their defaults.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Camera()
        yaw = try container.decodeIfPresent(Double.self, forKey: .yaw) ?? defaults.yaw
        pitch = try container.decodeIfPresent(Double.self, forKey: .pitch) ?? defaults.pitch
        roll = try container.decodeIfPresent(Double.self, forKey: .roll) ?? defaults.roll
        fieldOfView = try container.decodeIfPresent(Double.self, forKey: .fieldOfView) ?? defaults.fieldOfView
        zoom = try container.decodeIfPresent(Double.self, forKey: .zoom) ?? defaults.zoom
        fitToView = try container.decodeIfPresent(Bool.self, forKey: .fitToView) ?? defaults.fitToView
    }

    public var isOrthographic: Bool { fieldOfView < 1 }

    // MARK: - Views to start from

    public static let presets: [(name: String, camera: Camera)] = [
        ("Default", Camera()),
        ("Oblique, no perspective", Camera(yaw: -35, pitch: 25, fieldOfView: 0)),
        ("Isometric", Camera(yaw: -45, pitch: 35.264, fieldOfView: 0)),
        ("Front", Camera(yaw: 0, pitch: 0, fieldOfView: 0)),
        ("Side", Camera(yaw: 90, pitch: 0, fieldOfView: 0)),
        ("Top", Camera(yaw: 0, pitch: 90, fieldOfView: 0)),
        ("Wide angle", Camera(yaw: -30, pitch: 20, fieldOfView: 75)),
    ]

    // MARK: - Fitting

    /// How far the fitted cube reaches towards the edge of its cell, leaving a
    /// margin for dots, labels and the line width.
    public static let fitExtent = 0.9

    /// How much the picture must be scaled for the whole cube to fill its cell
    /// (up to `fitExtent`) from the current direction, at zoom 1. The same
    /// factor fits the inside area when `halfSize` is 1/3, because that area
    /// is a cube of its own.
    public var fitFactor: Double {
        var camera = self
        camera.zoom = 1
        camera.fitToView = false
        var extent = 0.0
        for sx in [-1.0, 1] { for sy in [-1.0, 1] { for sz in [-1.0, 1] {
            guard let p = camera.project(SIMD3(sx, sy, sz)) else { continue }
            extent = max(extent, abs(p.x), abs(p.y))
        } } }
        return extent > 0 ? Self.fitExtent / extent : 1
    }

    /// The camera to draw with: `fitToView` and `zoom` folded into a fixed
    /// zoom. Call this once per frame, not per point.
    public var resolved: Camera {
        var camera = self
        if fitToView { camera.zoom = zoom * fitFactor }
        camera.fitToView = false
        return camera
    }

    // MARK: - Rotation

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

    /// The rotation applied to model coordinates: yaw first, then pitch, then roll.
    public var rotation: simd_double3x3 {
        let (sy, cy) = (sin(Self.radians(yaw)), cos(Self.radians(yaw)))
        let (sp, cp) = (sin(Self.radians(pitch)), cos(Self.radians(pitch)))
        let (sr, cr) = (sin(Self.radians(roll)), cos(Self.radians(roll)))
        let aboutY = simd_double3x3(rows: [SIMD3(cy, 0, sy), SIMD3(0, 1, 0), SIMD3(-sy, 0, cy)])
        let aboutX = simd_double3x3(rows: [SIMD3(1, 0, 0), SIMD3(0, cp, -sp), SIMD3(0, sp, cp)])
        let aboutZ = simd_double3x3(rows: [SIMD3(cr, -sr, 0), SIMD3(sr, cr, 0), SIMD3(0, 0, 1)])
        return aboutZ * aboutX * aboutY
    }

    /// Drag the scene: `dx` turns it about the vertical axis, `dy` about the
    /// horizontal one, both in degrees. Angles wrap at 180.
    public mutating func orbit(dx: Double, dy: Double) {
        yaw = Self.wrapped(yaw + dx)
        pitch = Self.wrapped(pitch + dy)
    }

    public mutating func rotateAboutViewAxis(by degrees: Double) {
        roll = Self.wrapped(roll + degrees)
    }

    /// Change the perspective by `degrees` of field of view, within its range.
    public mutating func adjustFieldOfView(by degrees: Double) {
        fieldOfView = min(max(fieldOfView + degrees, Self.fieldOfViewRange.lowerBound), Self.fieldOfViewRange.upperBound)
    }

    public mutating func scaleZoom(by factor: Double) {
        zoom = min(max(zoom * factor, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    static func wrapped(_ angle: Double) -> Double {
        var value = angle.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value <= -180 { value += 360 }
        return value
    }

    // MARK: - Projection

    /// Radius of the sphere around a cube of the given half size.
    private func framingRadius(halfSize: Double) -> Double { 3.0.squareRoot() * halfSize }

    /// How far the camera is from the centre.
    private func distance(halfSize: Double) -> Double {
        framingRadius(halfSize: halfSize) / sin(Self.radians(fieldOfView) / 2)
    }

    /// Nearest distance in front of the camera that is still drawn, as a
    /// fraction of the camera distance.
    private static let nearFraction = 0.02

    private func projectView(_ v: SIMD3<Double>, halfSize: Double) -> ProjectedPoint {
        let radius = framingRadius(halfSize: halfSize)
        if isOrthographic {
            return ProjectedPoint(x: v.x / radius * zoom, y: v.y / radius * zoom, scale: 1, depth: -v.z)
        }
        let d = distance(halfSize: halfSize)
        let w = d - v.z                                        // distance along the view axis
        let focal = 1 / tan(Self.radians(fieldOfView) / 2)
        return ProjectedPoint(x: v.x * focal / w * zoom, y: v.y * focal / w * zoom, scale: d / w, depth: -v.z)
    }

    private func isInFront(_ v: SIMD3<Double>, halfSize: Double) -> Bool {
        isOrthographic || (distance(halfSize: halfSize) - v.z) > distance(halfSize: halfSize) * Self.nearFraction
    }

    /// Projects a model point. `halfSize` is the half width of the cube the
    /// view is framed on (1 for the whole cube, 1/3 to look at the middle third).
    /// Returns nil for a point behind the camera.
    public func project(_ point: SIMD3<Double>, halfSize: Double = 1) -> ProjectedPoint? {
        let v = rotation * point
        guard isInFront(v, halfSize: halfSize) else { return nil }
        return projectView(v, halfSize: halfSize)
    }

    /// Projects a line segment, cutting it at the near plane where it passes
    /// behind the camera. Returns nil when nothing of it is in front.
    public func project(from a: SIMD3<Double>, to b: SIMD3<Double>, halfSize: Double = 1)
        -> (ProjectedPoint, ProjectedPoint)? {
        var va = rotation * a
        var vb = rotation * b
        if !isOrthographic {
            let d = distance(halfSize: halfSize)
            let near = d * Self.nearFraction
            let wa = d - va.z, wb = d - vb.z
            if wa <= near && wb <= near { return nil }
            if wa <= near {
                va += (vb - va) * ((near - wa) / (wb - wa))
            } else if wb <= near {
                vb = va + (vb - va) * ((wa - near) / (wa - wb))
            }
        }
        return (projectView(va, halfSize: halfSize), projectView(vb, halfSize: halfSize))
    }

    /// Position in `rect` (y down, as in UI coordinates). One scale in both
    /// directions, so the picture is never distorted by the shape of the rect;
    /// the unit circle of the projection is fitted to the rect minus `inset`
    /// (a fraction of its size on each side) and centred in it.
    public func screen(_ point: ProjectedPoint, in rect: CGRect, inset: Double = 0.05) -> CGPoint {
        let half = min(rect.width, rect.height) / 2 * (1 - 2 * inset)
        return CGPoint(x: rect.midX + point.x * half, y: rect.midY - point.y * half)
    }
}
