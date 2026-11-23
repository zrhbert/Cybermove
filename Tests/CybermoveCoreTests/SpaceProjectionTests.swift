import CoreGraphics
import Foundation
import Testing
@testable import CybermoveCore

@Suite struct GraphicsModeTests {
    @Test func cubeGridsMatchCMO() {
        // mono 4x8, stereo 4x4, quadro 4x2, okto 2x2; always covering 32 signals
        #expect(GraphicsMode.mono.rows * GraphicsMode.mono.columns == 32)
        #expect(GraphicsMode.stereo.rows * GraphicsMode.stereo.columns == 16)
        #expect(GraphicsMode.quadro.rows * GraphicsMode.quadro.columns == 8)
        #expect(GraphicsMode.okto.rows * GraphicsMode.okto.columns == 4)
        for mode in GraphicsMode.allCases {
            #expect(mode.cubeCount * mode.signalsPerCube == 32)
            #expect(mode.rows * mode.columns == mode.cubeCount)
        }
    }

    @Test func signalsAreAssignedInOrder() {
        #expect(GraphicsMode.quadro.signals(inCube: 0) == 0..<4)
        #expect(GraphicsMode.quadro.signals(inCube: 7) == 28..<32)
        #expect(GraphicsMode.okto.signals(inCube: 3) == 24..<32)
    }
}

@Suite struct SpaceProjectionTests {
    private let rect = CGRect(x: 0, y: 0, width: 200, height: 100)

    @Test func nearCornerIsLowerLeftAndFarCornerUpperRight() {
        let projection = SpaceProjection()
        let near = projection.screen(x: -1, y: -1, z: 1, in: rect)
        let far = projection.screen(x: 1, y: 1, z: -1, in: rect)
        #expect(near.x < far.x)
        #expect(near.y > far.y)        // UI y grows downwards, near is lower
    }

    @Test func depthShiftsLeftAndDownTowardsTheViewer() {
        let projection = SpaceProjection()
        let back = projection.screen(x: 0, y: 0, z: -1, in: rect)
        let front = projection.screen(x: 0, y: 0, z: 1, in: rect)
        #expect(front.x < back.x)
        #expect(front.y > back.y)
    }

    @Test func cubeFillsTheRectMinusInset() {
        let projection = SpaceProjection()
        var points: [CGPoint] = []
        for x in [-1.0, 1.0] { for y in [-1.0, 1.0] { for z in [-1.0, 1.0] {
            points.append(projection.screen(x: x, y: y, z: z, in: rect, inset: 0.1))
        } } }
        #expect(abs(points.map(\.x).min()! - 20) < 0.001)
        #expect(abs(points.map(\.x).max()! - 180) < 0.001)
        #expect(abs(points.map(\.y).min()! - 10) < 0.001)
        #expect(abs(points.map(\.y).max()! - 90) < 0.001)
    }

    @Test func rotationAnglesUseRealtimersIntegerShift() {
        // 100 * sin(60 deg) = 86.6 -> 86 -> 86/128; 100 * sin(50 deg) = 76.6 -> 76 -> 76/128
        let plane = SpaceProjection().plane(x: 0, y: 0, z: 1)
        #expect(abs(plane.x - (-86.0 / 128)) < 1e-9)
        #expect(abs(plane.y - (-76.0 / 128)) < 1e-9)
    }

    @Test func unitPositionScalesWireRangeToTheCube() {
        #expect(SignalState(x: -64, y: 0, z: 63, volume: 127).unitPosition.x == -1)
        #expect(SignalState(x: 32).unitPosition.x == 0.5)
        #expect(SignalState(volume: 127).unitVolume == 1)
    }
}
