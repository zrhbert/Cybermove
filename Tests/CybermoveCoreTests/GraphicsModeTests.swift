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

@Suite struct SignalPositionTests {
    @Test func unitPositionMapsPlusMinus63ToTheCubeEdges() {
        let state = SignalState(x: 63, y: -63, z: 0, volume: 127)
        #expect(state.unitPosition == SIMD3(1, -1, 0))
        #expect(state.unitVolume == 1)
    }
}
