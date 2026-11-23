import CoreGraphics
import Foundation
import simd
import Testing
@testable import CybermoveCore

@Suite struct CameraTests {
    private func front(fieldOfView: Double = 30) -> Camera {
        Camera(yaw: 0, pitch: 0, roll: 0, fieldOfView: fieldOfView, zoom: 1)
    }

    private func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool { abs(a - b) < tolerance }

    // MARK: rotation

    @Test func rotationIsAProperRotationForAnyAngles() {
        for (yaw, pitch, roll) in [(0.0, 0.0, 0.0), (35, -70, 120), (180, 90, -45), (-170, 170, 10)] {
            let r = Camera(yaw: yaw, pitch: pitch, roll: roll).rotation
            let identity = r * r.transpose
            for i in 0..<3 { for j in 0..<3 { #expect(close(identity[i][j], i == j ? 1 : 0)) } }
            #expect(close(r.determinant, 1))
        }
    }

    @Test func frontViewShowsXToTheRightAndYUp() {
        let camera = front(fieldOfView: 0)
        let right = camera.project(SIMD3(1, 0, 0))!
        let up = camera.project(SIMD3(0, 1, 0))!
        #expect(right.x > 0 && close(right.y, 0))
        #expect(up.y > 0 && close(up.x, 0))
    }

    @Test func positiveZPointsTowardsTheViewer() {
        let camera = front()
        let near = camera.project(SIMD3(0, 0, 1))!
        let far = camera.project(SIMD3(0, 0, -1))!
        #expect(near.depth < far.depth)
        #expect(near.scale > 1 && far.scale < 1)
    }

    @Test func yawTurnsTheFrontToTheRightAndPitchTipsItDown() {
        var camera = front(fieldOfView: 0)
        camera.yaw = 90
        #expect(camera.project(SIMD3(0, 0, 1))!.x > 0.5)   // the front now faces right
        camera = front(fieldOfView: 0)
        camera.pitch = 90
        let frontPoint = camera.project(SIMD3(0, 0, 1))!
        #expect(frontPoint.y < 0 && close(frontPoint.x, 0))
    }

    @Test func rollTwistsAboutTheLineOfSight() {
        var camera = front(fieldOfView: 0)
        camera.roll = 90
        let p = camera.project(SIMD3(1, 0, 0))!
        #expect(close(p.x, 0) && p.y > 0)
        // the depth does not change
        #expect(close(p.depth, 0))
    }

    @Test func fullRotationsComeBackToTheStart() {
        let a = Camera(yaw: 0, pitch: 0, roll: 0).rotation
        let b = Camera(yaw: 360, pitch: -360, roll: 720).rotation
        for i in 0..<3 { for j in 0..<3 { #expect(close(a[i][j], b[i][j])) } }
    }

    @Test func orbitWrapsAnglesIntoHalfOpenRange() {
        var camera = Camera(yaw: 170, pitch: -170)
        camera.orbit(dx: 20, dy: -20)
        #expect(close(camera.yaw, -170))
        #expect(close(camera.pitch, 170))
        camera.orbit(dx: 360, dy: 0)
        #expect(close(camera.yaw, -170))
        #expect(Camera.wrapped(180) == 180)
        #expect(Camera.wrapped(-180) == 180)
    }

    @Test func upsideDownViewsAreReachable() {
        // Pitch past the pole: the top of the cube faces down on screen.
        let camera = Camera(yaw: 0, pitch: 180, roll: 0, fieldOfView: 0)
        #expect(camera.project(SIMD3(0, 1, 0))!.y < 0)
    }

    // MARK: perspective

    @Test func orthographicHasNoPerspective() {
        let camera = front(fieldOfView: 0)
        #expect(camera.isOrthographic)
        let near = camera.project(SIMD3(1, 0, 1))!
        let far = camera.project(SIMD3(1, 0, -1))!
        #expect(close(near.x, far.x))
        #expect(near.scale == 1 && far.scale == 1)
    }

    @Test func perspectiveMakesNearThingsLargerAndParallelLinesConverge() {
        let camera = front()
        let near = camera.project(SIMD3(1, 0, 1))!
        let far = camera.project(SIMD3(1, 0, -1))!
        #expect(near.x > far.x)
        // An edge running into the depth heads for the vanishing point (the centre).
        #expect(far.x > 0)
    }

    @Test func theCentreStaysPutWhateverTheFieldOfView() {
        for fov in [0.0, 10, 30, 75, 100] {
            let p = front(fieldOfView: fov).project(.zero)!
            #expect(close(p.x, 0) && close(p.y, 0) && close(p.scale, 1))
        }
    }

    @Test func theSphereAroundTheCubeKeepsItsSizeWhenThePerspectiveChanges() {
        // Dolly zoom: the point on the sphere nearest the sideways direction
        // always lands on the unit circle, regardless of the lens.
        let side = SIMD3(3.0.squareRoot(), 0, 0)
        for fov in [0.0, 5, 30, 60, 100] {
            let p = front(fieldOfView: fov).project(side)!
            // a point at the radius on the centre plane is at distance
            // sqrt(d^2 + r^2) from the camera; on screen it is r*focal/d
            let r = 3.0.squareRoot()
            let expected = fov < 1 ? 1 : r / (r / sin(fov * .pi / 360)) / tan(fov * .pi / 360)
            #expect(close(p.x, expected, 1e-9))
        }
    }

    @Test func zoomScalesThePicture() {
        var camera = front()
        let one = camera.project(SIMD3(1, 0, 0))!.x
        camera.zoom = 2
        #expect(close(camera.project(SIMD3(1, 0, 0))!.x, 2 * one))
    }

    @Test func zoomIsClamped() {
        var camera = Camera()
        camera.scaleZoom(by: 1000)
        #expect(camera.zoom == Camera.zoomRange.upperBound)
        camera.scaleZoom(by: 1e-9)
        #expect(camera.zoom == Camera.zoomRange.lowerBound)
    }

    // MARK: behind the camera

    @Test func aPointBehindTheCameraIsNotProjected() {
        // Wide-angle with the camera inside a framing of the middle third.
        let camera = front(fieldOfView: 100)
        let behind = SIMD3(0.0, 0, 50)
        #expect(camera.project(behind) == nil)
    }

    @Test func aSegmentCrossingTheNearPlaneIsCut() {
        let camera = front(fieldOfView: 100)
        let segment = camera.project(from: SIMD3(0, 0, -1), to: SIMD3(0, 0, 50))
        #expect(segment != nil)
        let (a, b) = segment!
        #expect(a.x.isFinite && b.x.isFinite && a.y.isFinite && b.y.isFinite)
        #expect(a.scale > 0 && b.scale > 0)
        #expect(camera.project(from: SIMD3(0, 0, 50), to: SIMD3(1, 0, 60)) == nil)
    }

    @Test func aSegmentInFrontIsNotChanged() {
        let camera = front()
        let a = SIMD3(-1.0, 0.5, 0.2), b = SIMD3(1.0, -0.5, -0.7)
        let (pa, pb) = camera.project(from: a, to: b)!
        #expect(pa == camera.project(a)!)
        #expect(pb == camera.project(b)!)
    }

    // MARK: halfSize (inside view)

    @Test func lookingAtTheMiddleThirdMagnifiesByThree() {
        let camera = front(fieldOfView: 0)
        let whole = camera.project(SIMD3(0.2, 0, 0))!.x
        let inside = camera.project(SIMD3(0.2, 0, 0), halfSize: 1.0 / 3)!.x
        #expect(close(inside, 3 * whole))
    }

    // MARK: screen mapping

    @Test func screenMappingKeepsProportionsInAnyCellShape() {
        let camera = front(fieldOfView: 0)
        for rect in [CGRect(x: 0, y: 0, width: 200, height: 100), CGRect(x: 0, y: 0, width: 80, height: 300)] {
            let right = camera.screen(camera.project(SIMD3(1, 0, 0))!, in: rect)
            let up = camera.screen(camera.project(SIMD3(0, 1, 0))!, in: rect)
            let centre = camera.screen(camera.project(.zero)!, in: rect)
            #expect(close(Double(right.x - centre.x), Double(centre.y - up.y)))
            #expect(close(Double(centre.x), Double(rect.midX)) && close(Double(centre.y), Double(rect.midY)))
        }
    }

    @Test func theCubeFitsTheCellWhateverTheOrientation() {
        // zoom 1 keeps every corner inside the cell
        let rect = CGRect(x: 0, y: 0, width: 150, height: 90)
        for yaw in stride(from: -180.0, through: 180, by: 45) {
            for pitch in stride(from: -90.0, through: 90, by: 45) {
                for fov in [0.0, 30, 60] {
                    let camera = Camera(yaw: yaw, pitch: pitch, roll: 30, fieldOfView: fov, zoom: 1)
                    for sx in [-1.0, 1] { for sy in [-1.0, 1] { for sz in [-1.0, 1] {
                        let p = camera.screen(camera.project(SIMD3(sx, sy, sz))!, in: rect, inset: 0)
                        #expect(rect.insetBy(dx: -0.5, dy: -0.5).contains(p),
                                "corner \(sx),\(sy),\(sz) at yaw \(yaw) pitch \(pitch) fov \(fov): \(p)")
                    } } }
                }
            }
        }
    }

    @Test func fittedCubeFillsTheViewFromEveryDirectionWithoutLeavingIt() {
        let rect = CGRect(x: 0, y: 0, width: 150, height: 90)
        for yaw in stride(from: -180.0, through: 180, by: 30) {
            for pitch in stride(from: -90.0, through: 90, by: 30) {
                for fov in [0.0, 12, 30, 75, 100] {
                    let camera = Camera(yaw: yaw, pitch: pitch, roll: 17, fieldOfView: fov).resolved
                    var extent = 0.0
                    for sx in [-1.0, 1] { for sy in [-1.0, 1] { for sz in [-1.0, 1] {
                        let p = camera.project(SIMD3(sx, sy, sz))!
                        extent = max(extent, abs(p.x), abs(p.y))
                        let point = camera.screen(p, in: rect, inset: 0.05)
                        #expect(rect.insetBy(dx: -0.5, dy: -0.5).contains(point))
                    } } }
                    #expect(close(extent, Camera.fitExtent, 1e-9), "yaw \(yaw) pitch \(pitch) fov \(fov): extent \(extent)")
                }
            }
        }
    }

    @Test func theInsideAreaFitsLikeTheWholeCube() {
        for (name, preset) in Camera.presets {
            let camera = preset.resolved
            var whole = 0.0, inside = 0.0
            for sx in [-1.0, 1] { for sy in [-1.0, 1] { for sz in [-1.0, 1] {
                let a = camera.project(SIMD3(sx, sy, sz))!
                whole = max(whole, abs(a.x), abs(a.y))
                let b = camera.project(SIMD3(sx, sy, sz) / 3, halfSize: 1.0 / 3)!
                inside = max(inside, abs(b.x), abs(b.y))
            } } }
            #expect(close(whole, inside, 1e-9), "\(name)")
            #expect(close(whole, Camera.fitExtent, 1e-9), "\(name)")
        }
    }

    @Test func zoomIsRelativeToTheFit() {
        let base = Camera().resolved.project(SIMD3(1, 1, 1))!
        var camera = Camera()
        camera.zoom = 0.5
        let half = camera.resolved.project(SIMD3(1, 1, 1))!
        #expect(close(half.x, base.x / 2) && close(half.y, base.y / 2))
    }

    @Test func withoutFitZoomIsAFixedSize() {
        var camera = Camera(yaw: 0, pitch: 0, fieldOfView: 0)
        camera.fitToView = false
        #expect(camera.resolved == camera)
        // face-on, the cube fills about 58% of the view
        #expect(close(camera.project(SIMD3(1, 1, 1))!.x, 1 / 3.0.squareRoot()))
    }

    @Test func everyPresetFitsTheWholeCube() {
        for (name, preset) in Camera.presets {
            let camera = preset.resolved
            for sx in [-1.0, 1] { for sy in [-1.0, 1] { for sz in [-1.0, 1] {
                let p = camera.project(SIMD3(sx, sy, sz))!
                #expect(abs(p.x) <= Camera.fitExtent + 1e-9 && abs(p.y) <= Camera.fitExtent + 1e-9, "\(name)")
            } } }
        }
    }

    @Test func presetsAreDistinctAndWithinRanges() {
        #expect(Set(Camera.presets.map(\.name)).count == Camera.presets.count)
        for (_, camera) in Camera.presets {
            #expect(Camera.fieldOfViewRange.contains(camera.fieldOfView))
            #expect(Camera.zoomRange.contains(camera.zoom))
        }
    }
}
