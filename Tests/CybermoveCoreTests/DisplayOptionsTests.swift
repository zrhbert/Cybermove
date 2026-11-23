import Foundation
import Testing
@testable import CybermoveCore

@Suite struct DisplayOptionsTests {
    @Test func defaultsAreRealtimersA3DDefaults() {
        let options = DisplayOptions()
        #expect(options.rotationX == 60)
        #expect(options.rotationY == 50)
        #expect(options.perspective == 0)
        #expect(options.projection == SpaceProjection())
    }

    @Test func optionsSurviveStorage() {
        var options = DisplayOptions()
        options.rotationX = 30
        options.showCrosshairs = true
        options.insideView = true
        #expect(DisplayOptions(storedJSON: options.storedJSON) == options)
    }

    @Test func damagedStorageFallsBackToDefaults() {
        #expect(DisplayOptions(storedJSON: Data("not json".utf8)) == DisplayOptions())
        #expect(DisplayOptions(storedJSON: nil) == DisplayOptions())
    }

    @Test func perspectiveScalesByDepthLikeTheAtariTables() {
        let projection = SpaceProjection(rotationX: 0, rotationY: 0, perspective: 32)
        // sin(0) = 0: no depth shift, so only the scale shows. z = 1: 1 + 32/64 = 1.5
        #expect(abs(projection.plane(x: 1, y: 0, z: 1).x - 1.5) < 1e-12)
        // z = -1: 1 - 0.5 = 0.5
        #expect(abs(projection.plane(x: 1, y: 0, z: -1).x - 0.5) < 1e-12)
        // no perspective: no scaling
        #expect(SpaceProjection(rotationX: 0, rotationY: 0, perspective: 0).plane(x: 1, y: 0, z: 1).x == 1)
    }

    @Test func extremePerspectiveNeverFlipsOrCollapsesTheCube() {
        let projection = SpaceProjection(perspective: 1000)
        let far = projection.plane(x: 1, y: 1, z: -1)
        #expect(far.x.isFinite && far.y.isFinite)
    }
}
