import AppKit
import SwiftUI

/// Borderless panel that can become key (so Esc reaches it) without ever activating the app —
/// the source app must keep focus while the user picks a browser.
final class PickerPanel: NSPanel {
    var onDismissRequest: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onDismissRequest?()
    }
}

/// Owns the floating picker. The panel is created once at launch and reused, keeping
/// presentation well under the 100 ms budget.
final class PickerPanelController: NSObject, NSWindowDelegate {
    private let panel: PickerPanel
    private let discovery: BrowserDiscovery
    private let ruleStore: RuleStore
    private var clickOutsideMonitor: Any?
    private var keyMonitor: Any?
    private var warnedAboutMissingClickOutsideMonitor = false

    // What is currently on screen, so a keystroke resolves to the same row a click would.
    private var presentedURLs: [URL] = []
    private var presentedBrowsers: [Browser] = []
    private var presentedDestinations: [LinkRouterCore.Destination] = []
    private var presentedMouseLocation: CGPoint = .zero
    private var state = PickerPanelState(remember: false)

    init(discovery: BrowserDiscovery, ruleStore: RuleStore) {
        self.discovery = discovery
        self.ruleStore = ruleStore
        panel = PickerPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.onDismissRequest = { [weak self] in self?.dismiss() }
    }

    func present(urls: [URL]) {
        let matched = urls.first.flatMap { RuleTable.firstMatch(for: $0, in: ruleStore.compiled) }
        let pinnedBundleID = matched?.rule.destination.browserBundleID
        let visible = LinkRouterCore.visibleBrowsers(discovery.browsers, hiddenIDs: Preferences.hiddenBrowserBundleIDs, id: \.id)
        let browsers = LinkRouterCore.moveToFront(visible, matching: pinnedBundleID, id: \.id)
        // A pinned site pre-checks the box, so confirming with return keeps the rule rather than
        // silently dropping it.
        let state = PickerPanelState(remember: pinnedBundleID != nil)
        presentedURLs = urls
        presentedBrowsers = browsers
        presentedDestinations = LinkRouterCore.destinations(profileCounts: browsers.map(\.profiles.count))
        presentedMouseLocation = NSEvent.mouseLocation
        self.state = state

        let content = PickerView(
            urls: urls,
            browsers: browsers,
            pinnedBundleID: pinnedBundleID,
            state: state
        ) { [weak self] browser, profile in
            self?.choose(browser, profile: profile)
        }
        let hostingView = NSHostingView(rootView: content)
        panel.contentView = hostingView
        panel.setContentSize(hostingView.fittingSize)
        panel.setFrameOrigin(LinkRouterCore.panelOrigin(
            panelSize: panel.frame.size,
            mouseLocation: presentedMouseLocation,
            screenVisibleFrame: screenVisibleFrameUnderMouse()
        ))
        panel.makeKeyAndOrderFront(nil)
        installClickOutsideMonitor()
        installKeyMonitor()
        // Self-heal the cache after showing so a freshly (un)installed browser appears next time
        // without delaying this presentation.
        Task { discovery.refresh() }
    }

    /// Opens the links and, when the remember box is checked, writes a host rule for this choice.
    /// Unchecking never deletes: rules are removed in Settings, where the user can see what they
    /// are removing — not from a checkbox in a panel that lives for a quarter of a second.
    private func choose(_ browser: Browser, profile: BrowserProfile?) {
        let urls = presentedURLs
        guard !urls.isEmpty else {
            dismiss()
            return
        }
        if let url = urls.first, state.remember,
           let host = MatchSubjectResolver.subject(.host, for: url) {
            let destination = RuleDestination(browserBundleID: browser.id, profileID: profile?.id)
            if var existing = RuleTable.firstMatch(for: url, in: ruleStore.compiled)?.rule {
                existing.destination = destination
                ruleStore.update(existing)
            } else {
                ruleStore.add(RoutingRule(
                    name: host,
                    matcher: .host(HostMatcher(host: host, includesSubdomains: false)),
                    destination: destination))
            }
        }
        discovery.open(urls, with: browser, profile: profile)
        dismiss()
    }

    func dismiss() {
        removeClickOutsideMonitor()
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        dismiss()
    }

    private func screenVisibleFrameUnderMouse() -> CGRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        return screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    // Global monitors only see events in other apps — exactly the "clicked elsewhere" signal.
    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        // Global monitors need Accessibility trust; without it the panel still dismisses through
        // windowDidResignKey, so this is degraded but recovered.
        if clickOutsideMonitor == nil, !warnedAboutMissingClickOutsideMonitor {
            warnedAboutMissingClickOutsideMonitor = true
            AppLog.warn("click-outside monitor unavailable, accessibility not trusted")
        }
    }

    // The panel is key without activating the app, so its keystrokes arrive as local events.
    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Only plain values cross into the isolated closure; NSEvent itself is not Sendable.
            let keyCode = event.keyCode
            let characters = event.charactersIgnoringModifiers
            // Modified keystrokes belong to the system, not to the picker.
            let isModified = !event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            let consumed = MainActor.assumeIsolated {
                self.handleKeyDown(keyCode: keyCode, characters: characters, isModified: isModified)
            }
            return consumed ? nil : event
        }
    }

    /// True when the picker acted on the key; everything it declines flows on untouched. The
    /// policy itself lives in `LinkRouterCore.pickerKeyAction` where it is unit-tested.
    private func handleKeyDown(keyCode: UInt16, characters: String?, isModified: Bool) -> Bool {
        guard panel.isVisible else { return false }
        switch LinkRouterCore.pickerKeyAction(
            keyCode: keyCode,
            characters: characters,
            isModified: isModified,
            destinationCount: presentedDestinations.count
        ) {
        case .open(let index):
            open(presentedDestinations[index])
            return true
        case .toggleLegend:
            state.showsLegend.toggle()
            resize()
            return true
        case .pass:
            return false
        }
    }

    /// Resolves a destination back to the browser and profile it stands for.
    private func open(_ destination: LinkRouterCore.Destination) {
        guard let destination = LinkRouterCore.resolvedDestination(destination, profileCounts: presentedBrowsers.map(\.profiles.count)) else { return }
        let browser = presentedBrowsers[destination.browser]
        let profile = destination.profile.map { browser.profiles[$0] }
        choose(browser, profile: profile)
    }

    /// The legend adds rows, so the panel has to grow and shrink with it — and stay clamped to the
    /// screen it was placed on. Deferred a tick because SwiftUI has not laid out the new content
    /// at the moment the key is handled.
    private func resize() {
        Task { @MainActor [weak self] in
            guard let self, let hostingView = panel.contentView, panel.isVisible else { return }
            hostingView.layoutSubtreeIfNeeded()
            panel.setContentSize(hostingView.fittingSize)
            panel.setFrameOrigin(LinkRouterCore.panelOrigin(
                panelSize: panel.frame.size,
                mouseLocation: presentedMouseLocation,
                screenVisibleFrame: screenVisibleFrameUnderMouse()
            ))
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func removeClickOutsideMonitor() {
        if let clickOutsideMonitor {
            NSEvent.removeMonitor(clickOutsideMonitor)
            self.clickOutsideMonitor = nil
        }
    }
}
