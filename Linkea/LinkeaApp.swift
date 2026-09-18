import SwiftUI

/// Linkea runs as a menu-bar agent (LSUIElement): no Dock icon, no main window, so an
/// intercepted link never yanks focus away from the app the user clicked in. The single
/// settings window (setup + rules) is owned by the AppDelegate, not by a scene.
@main struct LinkeaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Template PDF rather than an SF Symbol: the mark is Linkea's own, and macOS tints it
        // for the light and dark menu bar on its own.
        MenuBarExtra("Linkea", image: "MenuBarIcon") {
            Button("Settings…") {
                appDelegate.showSettings()
            }
            Toggle("Pause rules", isOn: Bindable(appDelegate.ruleStore).isPaused)
            Divider()
            Button("Quit Linkea") {
                NSApp.terminate(nil)
            }
        }
    }
}
