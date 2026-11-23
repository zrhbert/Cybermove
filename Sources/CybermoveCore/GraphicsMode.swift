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

extension SignalState {
    /// Position in the cube [-1, 1]^3. Realtimer maps +-63 (its MAXKOOR) onto the
    /// cube edges, so +63 is exactly 1; the wire value -64 lands just outside,
    /// as it does on the Atari. +z points towards the viewer.
    public var unitPosition: SIMD3<Double> {
        SIMD3(Double(x) / 63, Double(y) / 63, Double(z) / 63)
    }

    /// Volume as 0...1.
    public var unitVolume: Double { Double(volume) / 127 }
}
