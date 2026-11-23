import Foundation

/// How the cubes are drawn.
public struct DisplayOptions: Equatable, Codable, Sendable {
    /// The view of the cubes, shared by all of them.
    public var camera = Camera()
    /// "Innenraum": look at the middle third of the cube only, as Realtimer's
    /// inside view does. Points outside it are cut off by the cell.
    public var insideView = false
    /// In the full view, dotted squares on every face of the cube mark the area
    /// the inside view looks at, as Realtimer's cube does.
    public var markInsideArea = true

    /// The lines that join signals (to the centre in mono, in pairs in stereo,
    /// along the whole group in quadro and okto).
    public var showLines = true
    /// "Fadenkreuz": a line along each axis through every point.
    public var showCrosshairs = false
    /// Horizontal volume bars along the bottom of each cube, as in Realtimer.
    public var showVolumeBars = false
    /// The signal number beside each point that has data.
    public var showSignalNumbers = false
    /// Dots grow with the signal's volume.
    public var dotSizeFollowsVolume = true
    /// With perspective, nearer points are drawn larger and farther ones smaller.
    public var depthCues = true
    /// A small X, Y, Z indicator that shows how the view is turned.
    public var showAxes = true

    public init() {}

    /// Missing keys keep their defaults, so settings stored by an older version
    /// (before an option existed, or with options that no longer exist) still
    /// load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = DisplayOptions()
        camera = try container.decodeIfPresent(Camera.self, forKey: .camera) ?? defaults.camera
        insideView = try container.decodeIfPresent(Bool.self, forKey: .insideView) ?? defaults.insideView
        markInsideArea = try container.decodeIfPresent(Bool.self, forKey: .markInsideArea) ?? defaults.markInsideArea
        showLines = try container.decodeIfPresent(Bool.self, forKey: .showLines) ?? defaults.showLines
        showCrosshairs = try container.decodeIfPresent(Bool.self, forKey: .showCrosshairs) ?? defaults.showCrosshairs
        showVolumeBars = try container.decodeIfPresent(Bool.self, forKey: .showVolumeBars) ?? defaults.showVolumeBars
        showSignalNumbers = try container.decodeIfPresent(Bool.self, forKey: .showSignalNumbers) ?? defaults.showSignalNumbers
        dotSizeFollowsVolume = try container.decodeIfPresent(Bool.self, forKey: .dotSizeFollowsVolume)
            ?? defaults.dotSizeFollowsVolume
        depthCues = try container.decodeIfPresent(Bool.self, forKey: .depthCues) ?? defaults.depthCues
        showAxes = try container.decodeIfPresent(Bool.self, forKey: .showAxes) ?? defaults.showAxes
    }

    /// Stored as JSON in the user defaults. Unknown or damaged data gives the defaults.
    public init(storedJSON: Data?) {
        if let storedJSON, let decoded = try? JSONDecoder().decode(DisplayOptions.self, from: storedJSON) {
            self = decoded
        }
    }

    public var storedJSON: Data? { try? JSONEncoder().encode(self) }
}
