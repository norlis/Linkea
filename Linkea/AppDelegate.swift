import AppKit
import SwiftUI

/// Lifecycle hub: receives system-opened URLs and decides between showing the picker
/// (link click) and showing the settings window (first manual launch).
final class AppDelegate: NSObject, NSApplicationDelegate {
    let discovery = BrowserDiscovery()
    let defaultBrowserManager = DefaultBrowserManager()
    let ruleStore = RuleStore()

    private var pickerController: PickerPanelController?
    private var settingsWindow: NSWindow?
    private var didReceiveURLThisLaunch = false

    // Kept for the app's lifetime; never cancelled because the delegate never dies.
    private var windowCloseTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        discovery.refresh()
        pickerController = PickerPanelController(discovery: discovery, ruleStore: ruleStore)
        // .map strips the non-Sendable Notification before it crosses into this task.
        windowCloseTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSWindow.willCloseNotification).map({ _ in () }) {
                // willClose fires before the window leaves the list; let the close finish first.
                try? await Task.sleep(for: .milliseconds(50))
                self?.handlePossibleLastWindowClose()
            }
        }
        AppLog.info("app launched", fields: ["browser.count": String(discovery.browsers.count)])
        guard !Preferences.onboardingCompleted else { return }
        // URL-triggered launches deliver application(_:open:) right after this callback; the
        // short deferral plus the flag keeps the window from flashing over an intercepted link.
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            if !didReceiveURLThisLaunch {
                showSettings()
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

        // Option forces the picker; pausing does the same without depending on key timing.
        let forcePicker = NSEvent.modifierFlags.contains(.option) || ruleStore.isPaused
        let decision: RuleRouter.Decision = forcePicker
            ? .ask
            : RuleRouter.resolve(urls: webURLs, rules: ruleStore.compiled) { discovery.canResolve($0) }

        switch decision {
        case .route(let destination):
            AppLog.info("rule routed link", fields: [
                "url.domain": webURLs.first?.host() ?? "",
                "destination.bundle_id": destination.browserBundleID
            ])
            discovery.open(webURLs, destination: destination)
        case .ask:
            pickerController?.present(urls: webURLs)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    /// An LSUIElement app is invisible to Cmd+Tab, which strands its windows the moment the user
    /// switches away. While a real window is open the app joins the Dock and the switcher; it
    /// returns to agent mode when the last one closes. The picker panel never triggers this.
    func promoteToRegularApp() {
        installEditMenuIfMissing()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Cmd+V/C/X only reach a text field by resolving through an Edit menu in the main menu bar,
    /// and an agent app is not guaranteed one — without it, paste is dead in every settings field.
    private func installEditMenuIfMissing() {
        let mainMenu = NSApp.mainMenu ?? NSMenu()
        guard !mainMenu.items.contains(where: { $0.submenu?.title == "Edit" }) else { return }
        let edit = NSMenu(title: "Edit")
        // undo:/redo: have no typed selector to reference; they are resolved by the first
        // responder's UndoManager at dispatch time, which is exactly what a menu item does.
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Select All", action: #selector(NSStandardKeyBindingResponding.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    /// Once the last real window closes the app leaves the Dock again, and having seen and closed
    /// the settings window is the whole setup ceremony — no separate "Done" step.
    private func handlePossibleLastWindowClose() {
        let hasUserWindow = NSApp.windows.contains {
            $0.isVisible && !($0 is NSPanel) && $0.styleMask.contains(.titled)
        }
        guard !hasUserWindow else { return }
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
        if !Preferences.onboardingCompleted {
            Preferences.onboardingCompleted = true
        }
    }

    func showSettings() {
        promoteToRegularApp()
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }
        let view = SettingsRootView(
            manager: defaultBrowserManager,
            discovery: discovery,
            store: ruleStore,
            onTryIt: { [weak self] in
                self?.application(NSApp, open: [LinkRouterCore.probeURL])
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
        settingsWindow = window
    }
}
