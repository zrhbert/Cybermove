import Foundation

/// How the cubes are drawn. The first group mirrors the settings of Realtimer's
/// 3D displays; the defaults are Realtimer's.
public struct DisplayOptions: Equatable, Codable, Sendable {
    /// "LR-Rot": how far depth shifts a point sideways, in degrees.
    public var rotationX: Double = 60
    /// "OU-Rot": how far depth shifts a point up or down, in degrees.
    public var rotationY: Double = 50
    /// "Wirkung": depth scaling, 0 for none.
    public var perspective: Double = 0
    /// "Innenraum": zoom in on the middle third of the cube, as Realtimer's
    /// inside view does. Points outside are held at the edge of the cell.
    public var insideView = false

    /// In the full view, dotted squares on every face of the cube mark the area
    /// the inside view zooms in on, as Realtimer's cube does.
    public var markInsideArea = true

    /// The lines that join signals (to the centre in mono, in pairs in stereo,
    /// along the whole group in quadro and okto).
    public var showLines = true
    /// "Fadenkreuz": a line along each axis through every point.
    public var showCrosshairs = false
    /// Horizontal volume bars along the bottom of each cube, as in Realtimer.
    public var showVolumeBars = false
    /// The signal number beside each point.
    public var showSignalNumbers = false
    /// Dots grow with the signal's volume.
    public var dotSizeFollowsVolume = true

    public init() {}

    /// Missing keys keep their defaults, so settings stored by an older version
    /// (before an option existed) are not thrown away.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = DisplayOptions()
        rotationX = try container.decodeIfPresent(Double.self, forKey: .rotationX) ?? defaults.rotationX
        rotationY = try container.decodeIfPresent(Double.self, forKey: .rotationY) ?? defaults.rotationY
        perspective = try container.decodeIfPresent(Double.self, forKey: .perspective) ?? defaults.perspective
        insideView = try container.decodeIfPresent(Bool.self, forKey: .insideView) ?? defaults.insideView
        markInsideArea = try container.decodeIfPresent(Bool.self, forKey: .markInsideArea) ?? defaults.markInsideArea
        showLines = try container.decodeIfPresent(Bool.self, forKey: .showLines) ?? defaults.showLines
        showCrosshairs = try container.decodeIfPresent(Bool.self, forKey: .showCrosshairs) ?? defaults.showCrosshairs
        showVolumeBars = try container.decodeIfPresent(Bool.self, forKey: .showVolumeBars) ?? defaults.showVolumeBars
        showSignalNumbers = try container.decodeIfPresent(Bool.self, forKey: .showSignalNumbers) ?? defaults.showSignalNumbers
        dotSizeFollowsVolume = try container.decodeIfPresent(Bool.self, forKey: .dotSizeFollowsVolume)
            ?? defaults.dotSizeFollowsVolume
    }

    public var projection: SpaceProjection {
        SpaceProjection(rotationX: rotationX, rotationY: rotationY, perspective: perspective)
    }

    /// Value ranges for the controls.
    public static let rotationRange: ClosedRange<Double> = 0...90
    public static let perspectiveRange: ClosedRange<Double> = 0...40

    /// Stored as JSON in the user defaults. Unknown or damaged data gives the defaults.
    public init(storedJSON: Data?) {
        if let storedJSON, let decoded = try? JSONDecoder().decode(DisplayOptions.self, from: storedJSON) {
            self = decoded
        }
    }

    public var storedJSON: Data? { try? JSONEncoder().encode(self) }
}
