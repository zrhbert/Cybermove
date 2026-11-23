import AppKit
import CybermoveCore
import SwiftUI

/// Turns mouse and trackpad input over the cubes into camera changes:
///
/// - drag: turn the cubes
/// - two-finger scroll (or the mouse wheel): zoom
/// - three fingers up or down on the trackpad: perspective
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
        /// Field of view when the three fingers cross the trackpad's whole height.
        private static let degreesPerTrackpadHeight = 120.0

        /// The three fingers' average height on the trackpad (0 bottom, 1 top).
        private var threeFingerHeight: Double?

        override init(frame: NSRect) {
            super.init(frame: frame)
            allowedTouchTypes = [.indirect]
        }

        required init?(coder: NSCoder) { fatalError("not used") }

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
            let rate = event.hasPreciseScrollingDeltas ? Self.zoomPerPoint : Self.zoomPerLine
            edit { $0.scaleZoom(by: exp(Double(event.scrollingDeltaY) * rate)) }
        }

        // MARK: Three fingers

        override func touchesBegan(with event: NSEvent) { trackThreeFingers(event) }
        override func touchesMoved(with event: NSEvent) { trackThreeFingers(event) }
        override func touchesEnded(with event: NSEvent) { trackThreeFingers(event) }
        override func touchesCancelled(with event: NSEvent) { threeFingerHeight = nil }

        private func trackThreeFingers(_ event: NSEvent) {
            let touches = event.touches(matching: .touching, in: self)
            guard touches.count == 3 else {
                threeFingerHeight = nil
                return
            }
            let height = touches.reduce(0.0) { $0 + Double($1.normalizedPosition.y) } / 3
            if let last = threeFingerHeight {
                edit { $0.adjustFieldOfView(by: (height - last) * Self.degreesPerTrackpadHeight) }
            }
            threeFingerHeight = height
        }
    }
}
