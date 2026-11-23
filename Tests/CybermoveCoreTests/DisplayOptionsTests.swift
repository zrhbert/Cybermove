import Foundation
import Testing
@testable import CybermoveCore

@Suite struct DisplayOptionsTests {
    @Test func defaultsAreAMildPerspectiveFromAboveAndTheLeft() {
        let options = DisplayOptions()
        #expect(options.camera == Camera())
        #expect(options.camera.fieldOfView > 0)
        #expect(options.markInsideArea)
        #expect(options.depthCues)
        #expect(!options.insideView)
    }

    @Test func optionsSurviveStorage() {
        var options = DisplayOptions()
        options.camera = Camera(yaw: 123, pitch: -77, roll: 15, fieldOfView: 55, zoom: 2)
        options.showCrosshairs = true
        options.insideView = true
        #expect(DisplayOptions(storedJSON: options.storedJSON) == options)
    }

    @Test func zoomPerspectiveAndFitAreStoredAndRestoredByReset() throws {
        var options = DisplayOptions()
        options.camera.zoom = 0.3
        options.camera.fieldOfView = 12
        options.camera.fitToView = false
        let data = try #require(options.storedJSON)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"zoom\":0.3") && json.contains("\"fieldOfView\":12") && json.contains("\"fitToView\":false"))
        #expect(DisplayOptions(storedJSON: options.storedJSON).camera == options.camera)
        #expect(DisplayOptions().camera.zoom == 1 && DisplayOptions().camera.fieldOfView == 30)
    }

    @Test func settingsFromAnOlderVersionKeepTheirValuesAndGetDefaultsForNewOptions() {
        // Version 0.2 stored the oblique angles, which no longer exist.
        let old = Data(#"{"rotationX":33,"showCrosshairs":true,"markInsideArea":false}"#.utf8)
        let options = DisplayOptions(storedJSON: old)
        #expect(options.showCrosshairs)
        #expect(!options.markInsideArea)
        #expect(options.camera == Camera())
        #expect(options.depthCues)
    }

    @Test func aCameraWithMissingKeysKeepsDefaults() {
        let stored = Data(#"{"camera":{"yaw":10}}"#.utf8)
        let options = DisplayOptions(storedJSON: stored)
        #expect(options.camera.yaw == 10)
        #expect(options.camera.pitch == Camera().pitch)
    }

    @Test func damagedStorageFallsBackToDefaults() {
        #expect(DisplayOptions(storedJSON: Data("not json".utf8)) == DisplayOptions())
        #expect(DisplayOptions(storedJSON: nil) == DisplayOptions())
    }
}
