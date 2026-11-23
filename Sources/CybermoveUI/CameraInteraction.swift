import AppKit
import CybermoveCore
import SwiftUI

/// Turns mouse and trackpad input over the cubes into camera changes:
///
/// - drag: turn the cubes
/// - two-finger scroll (or the mouse wheel): zoom
/// - the same with Command held: perspective
/// - pinch: zoom, rotate with two fingers: roll about the line of sight
/// - double-click: back to the default view
struct CameraInteraction: NSViewRepresentable {
    let camera: Camera
    let onChange: (Camera) -> Void

    func makeNSView(context: Context) -> InteractionView {
        InteractionView()
    }

    func updateNSView(_ view: InteractionView, context: Context) {
        view.camera = camera
        view.onChange = onChange
    }

    final class InteractionView: NSView {
        var camera = Camera()
        var onChange: ((Camera) -> Void)?

        /// Degrees of rotation per point of dragging.
        private static let degreesPerPoint = 0.5
        /// Zoom per point of two-finger scrolling, and per line of a mouse wheel.
        private static let zoomPerPoint = 0.005
        private static let zoomPerLine = 0.05
        /// Degrees of field of view per point of Command-scrolling, and per wheel line.
        private static let perspectivePerPoint = 0.2
        private static let perspectivePerLine = 2.0

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        /// Apply a change to the latest camera, remembering it here at once
        /// because the next event can arrive before SwiftUI hands the new one back.
        private func edit(_ change: (inout Camera) -> Void) {
            var updated = camera
            change(&updated)
            guard updated != camera else { return }
            camera = updated
            onChange?(updated)
        }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { edit { $0 = Camera() } }
        }

        override func mouseDragged(with event: NSEvent) {
            edit { $0.orbit(dx: Double(event.deltaX) * Self.degreesPerPoint,
                            dy: Double(event.deltaY) * Self.degreesPerPoint) }
        }

        override func magnify(with event: NSEvent) {
            edit { $0.scaleZoom(by: 1 + Double(event.magnification)) }
        }

        override func rotate(with event: NSEvent) {
            edit { $0.rotateAboutViewAxis(by: Double(event.rotation)) }     // counterclockwise is positive
        }

        override func scrollWheel(with event: NSEvent) {
            // Momentum after the fingers lift would zoom on by itself.
            guard event.momentumPhase.isEmpty else { return }
            let precise = event.hasPreciseScrollingDeltas
            let delta = Double(event.scrollingDeltaY)
            if event.modifierFlags.contains(.command) {
                edit { $0.adjustFieldOfView(by: delta * (precise ? Self.perspectivePerPoint : Self.perspectivePerLine)) }
            } else {
                edit { $0.scaleZoom(by: exp(delta * (precise ? Self.zoomPerPoint : Self.zoomPerLine))) }
            }
        }
    }
}
