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

    private func cornerBounds(in rect: CGRect, inset: Double = 0.1) -> CGRect {
        let projection = SpaceProjection()
        var points: [CGPoint] = []
        for x in [-1.0, 1.0] { for y in [-1.0, 1.0] { for z in [-1.0, 1.0] {
            points.append(projection.screen(x: x, y: y, z: z, in: rect, inset: inset))
        } } }
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    @Test func cubeFitsInsideTheRectAndTouchesTheLimitingSide() {
        // a wide cell: the height limits, the cube is centred sideways
        let wide = cornerBounds(in: CGRect(x: 0, y: 0, width: 400, height: 100))
        #expect(abs(wide.height - 80) < 0.001)
        #expect(abs(wide.midX - 200) < 0.001 && abs(wide.midY - 50) < 0.001)
        // a tall cell: the width limits, the cube is centred vertically
        let tall = cornerBounds(in: CGRect(x: 0, y: 0, width: 100, height: 400))
        #expect(abs(tall.width - 80) < 0.001)
        #expect(abs(tall.midX - 50) < 0.001 && abs(tall.midY - 200) < 0.001)
    }

    @Test func cubeKeepsItsProportionsInAnyCellShape() {
        let wide = cornerBounds(in: CGRect(x: 0, y: 0, width: 400, height: 100))
        let tall = cornerBounds(in: CGRect(x: 0, y: 0, width: 100, height: 400))
        let square = cornerBounds(in: CGRect(x: 0, y: 0, width: 200, height: 200))
        let ratio = square.width / square.height
        #expect(abs(wide.width / wide.height - ratio) < 1e-9)
        #expect(abs(tall.width / tall.height - ratio) < 1e-9)
    }

    @Test func oneUnitIsTheSameLengthAlongX_YAndZ() {
        let projection = SpaceProjection()
        for rect in [CGRect(x: 0, y: 0, width: 400, height: 100), CGRect(x: 0, y: 0, width: 100, height: 400)] {
            let origin = projection.screen(x: 0, y: 0, z: 0, in: rect)
            let right = projection.screen(x: 1, y: 0, z: 0, in: rect)
            let up = projection.screen(x: 0, y: 1, z: 0, in: rect)
            #expect(abs((right.x - origin.x) - (origin.y - up.y)) < 1e-9)   // equal on screen
            #expect(abs(right.y - origin.y) < 1e-9 && abs(up.x - origin.x) < 1e-9)
        }
    }

    @Test func rotationAnglesUseRealtimersIntegerShift() {
        // 100 * sin(60 deg) = 86.6 -> 86 -> 86/128; 100 * sin(50 deg) = 76.6 -> 76 -> 76/128
        let plane = SpaceProjection().plane(x: 0, y: 0, z: 1)
        #expect(abs(plane.x - (-86.0 / 128)) < 1e-9)
        #expect(abs(plane.y - (-76.0 / 128)) < 1e-9)
    }

    @Test func unitPositionScalesWireRangeToTheCube() {
        #expect(SignalState(x: 63).unitPosition.x == 1)
        #expect(SignalState(x: -63).unitPosition.x == -1)
        #expect(abs(SignalState(x: -64).unitPosition.x - (-64.0 / 63)) < 1e-12)
        #expect(SignalState(volume: 127).unitVolume == 1)
    }
}
