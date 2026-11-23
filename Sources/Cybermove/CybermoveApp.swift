import CybermoveUI
import SwiftUI

@main
struct CybermoveApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var controller = MonitorController()

    var body: some Scene {
        WindowGroup("Cybermove") {
            MonitorView(controller: controller)
                .frame(minWidth: 900, minHeight: 620)
                .task { controller.start() }
        }
    }
}

/// A Swift package executable is not a bundled app, so ask for a normal
/// foreground presence (menu bar, dock icon, keyboard focus).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
