import CybermoveUI
import SwiftUI

@main
struct CybermoveApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var controller = MonitorController()

    var body: some Scene {
        WindowGroup("Cybermove") {
            MonitorView(controller: controller)
                .frame(minWidth: 1100, minHeight: 620)
                .task { controller.start() }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Cybermove") { showAbout() }
            }
        }
    }
}

/// The standard About box, with the time the app was built in place of the
/// build number. A plain `swift run` has no bundle to read it from.
@MainActor
private func showAbout() {
    let built = Bundle.main.object(forInfoDictionaryKey: "CybermoveBuildDate") as? String ?? "unknown (not an app bundle)"
    NSApp.orderFrontStandardAboutPanel(options: [.applicationVersion: "built \(built)"])
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
