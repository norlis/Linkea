import AppKit
import SwiftUI

/// Lifecycle hub: receives system-opened URLs and decides between showing the picker
/// (link click) and showing onboarding (first manual launch).
final class AppDelegate: NSObject, NSApplicationDelegate {
    let discovery = BrowserDiscovery()
    let defaultBrowserManager = DefaultBrowserManager()
    let ruleStore = RuleStore()

    private var pickerController: PickerPanelController?
    private var onboardingWindow: NSWindow?
    private var didReceiveURLThisLaunch = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        discovery.refresh()
        pickerController = PickerPanelController(discovery: discovery, ruleStore: ruleStore)
        AppLog.info("app launched", fields: ["browser.count": String(discovery.browsers.count)])
        guard !Preferences.onboardingCompleted else { return }
        // URL-triggered launches deliver application(_:open:) right after this callback; the
        // short deferral plus the flag keeps onboarding from flashing over an intercepted link.
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            if !didReceiveURLThisLaunch {
                showOnboarding()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let webURLs = LinkRouterCore.webURLs(from: urls)
        guard !webURLs.isEmpty else {
            AppLog.warn("received urls rejected by scheme allowlist", fields: ["url.count": String(urls.count)])
            return
        }
        didReceiveURLThisLaunch = true
        AppLog.info("routing urls", fields: [
            "url.count": String(webURLs.count),
            "url.scheme": webURLs.first?.scheme?.lowercased() ?? "",
            "url.domain": webURLs.first?.host() ?? ""
        ])
        pickerController?.present(urls: webURLs)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showOnboarding()
        return true
    }

    func showOnboarding() {
        // An LSUIElement app is never active on its own; activate or the window opens behind
        // everything else.
        NSApp.activate(ignoringOtherApps: true)
        if let onboardingWindow {
            onboardingWindow.makeKeyAndOrderFront(nil)
            return
        }
        let view = OnboardingView(
            manager: defaultBrowserManager,
            onTryIt: { [weak self] in
                self?.application(NSApp, open: [LinkRouterCore.probeURL])
            },
            onDone: { [weak self] in
                Preferences.onboardingCompleted = true
                self?.onboardingWindow?.close()
            }
        )
        let hostingController = NSHostingController(rootView: view)
        // Sizing via preferredContentSize avoids the AppKit "Update Constraints in Window pass"
        // layout loop that constraint-driven window sizing triggers with dynamic SwiftUI content.
        hostingController.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Linkea"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        onboardingWindow = window
    }
}
