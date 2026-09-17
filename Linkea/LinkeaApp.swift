import SwiftUI

/// Linkea runs as a menu-bar agent (LSUIElement): no Dock icon, no main window, so an
/// intercepted link never yanks focus away from the app the user clicked in.
@main struct LinkeaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Template PDF rather than an SF Symbol: the mark is Linkea's own, and macOS tints it
        // for the light and dark menu bar on its own.
        MenuBarExtra("Linkea", image: "MenuBarIcon") {
            Button("Open Linkea Setup…") {
                appDelegate.showOnboarding()
            }
            Divider()
            PinnedSitesMenu(store: appDelegate.ruleStore, discovery: appDelegate.discovery)
            Divider()
            Button("Quit Linkea") {
                NSApp.terminate(nil)
            }
        }
    }
}

/// The sites pinned to a browser, editable where the user already looks for Linkea.
private struct PinnedSitesMenu: View {
    let store: RuleStore
    let discovery: BrowserDiscovery

    var body: some View {
        let entries = store.rules.entries
        Menu("Pinned Sites") {
            if entries.isEmpty {
                Button("Nothing pinned yet") {}
                    .disabled(true)
            } else {
                Button("Click a site to unpin it") {}
                    .disabled(true)
                Divider()
                ForEach(entries, id: \.host) { entry in
                    Button("\(entry.host) → \(browserName(entry.bundleID))") {
                        store.forget(host: entry.host)
                    }
                }
                Divider()
                Button("Unpin All Sites") {
                    store.forgetAll()
                }
            }
        }
    }

    private func browserName(_ bundleID: String) -> String {
        discovery.browsers.first { $0.id == bundleID }?.name ?? bundleID
    }
}
