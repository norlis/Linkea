import AppKit
import ApplicationServices

/// Experimental Safari profile support. Safari exposes no API for profiles (no AppleScript, no
/// CLI arguments, TCC-protected data), so the only route is Accessibility: press the user-mapped
/// "New <profile> Window" item in Safari's File menu, then open the URL in that window.
/// Every failure falls back to opening in Safari without a profile — a link is never lost.
enum SafariProfileLauncher {
    static let safariBundleID = "com.apple.Safari"

    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    // kAXTrustedCheckOptionPrompt is imported as a mutable C global that the Swift 6 language
    // mode rejects at every reference; its documented value (AXUIElement.h) is duplicated here
    // because there is no concurrency-safe way to read the SDK constant.
    private static let trustedCheckOptionPromptKey = "AXTrustedCheckOptionPrompt"

    static func requestAccessibilityPermission() {
        let options = [trustedCheckOptionPromptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Profiles come from the user-confirmed menu mapping, never from guessing menu titles.
    static func configuredProfiles() -> [BrowserProfile] {
        guard Preferences.safariProfilesEnabled, isAccessibilityTrusted else { return [] }
        let titles = Preferences.safariProfileMenuTitles
        let names = ProfileCore.distinguishingNames(fromMenuTitles: titles)
        return zip(titles, names).map { title, name in
            BrowserProfile(id: title, displayName: name, recipe: .safariProfileMenuItem(title))
        }
    }

    /// Raw titles of Safari's File-menu items, for the mapping UI. Requires Safari running.
    static func fileMenuItemTitles() -> [String] {
        guard isAccessibilityTrusted, let safari = runningSafari() else { return [] }
        let app = AXUIElementCreateApplication(safari.processIdentifier)
        return fileMenuItems(of: app).compactMap(title(of:))
    }

    static func open(_ urls: [URL], menuItemTitle: String, safariAppURL: URL) {
        Task { @MainActor in
            let pressed = await pressProfileMenuItem(titled: menuItemTitle, safariAppURL: safariAppURL)
            if !pressed {
                AppLog.warn("safari profile window could not be opened, falling back to plain safari")
            }
            // Safari opens URLs as tabs of the frontmost window — the profile window when the
            // press succeeded, any window otherwise.
            do {
                _ = try await NSWorkspace.shared.open(urls, withApplicationAt: safariAppURL, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                AppLog.error("safari open failed", error: error, fields: ["app.bundle_id": safariBundleID])
            }
        }
    }

    // MARK: - Press flow

    private static func pressProfileMenuItem(titled title: String, safariAppURL: URL) async -> Bool {
        guard Preferences.safariProfilesEnabled, isAccessibilityTrusted else { return false }
        guard let safari = await ensureSafariRunning(at: safariAppURL) else { return false }
        // The profile window items only act on the active app's menu reliably.
        _ = safari.activate()
        let app = AXUIElementCreateApplication(safari.processIdentifier)

        for _ in 0..<2 {
            try? await Task.sleep(for: .milliseconds(200))
            guard let item = fileMenuItems(of: app).first(where: { self.title(of: $0) == title }) else { continue }
            let windowsBefore = windowCount(of: app)
            guard AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else { continue }
            var polls = 0
            while windowCount(of: app) <= windowsBefore, polls < 20 {
                try? await Task.sleep(for: .milliseconds(100))
                polls += 1
            }
            if windowCount(of: app) > windowsBefore {
                return true
            }
        }
        return false
    }

    private static func ensureSafariRunning(at appURL: URL) async -> NSRunningApplication? {
        if let running = runningSafari() {
            return running
        }
        do {
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        } catch {
            AppLog.error("safari launch failed", error: error, fields: ["app.bundle_id": safariBundleID])
            return nil
        }
        var polls = 0
        while polls < 50 {
            if let running = runningSafari(), running.isFinishedLaunching {
                return running
            }
            try? await Task.sleep(for: .milliseconds(100))
            polls += 1
        }
        return runningSafari()
    }

    private static func runningSafari() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: safariBundleID).first
    }

    // MARK: - Accessibility helpers

    private static func fileMenuItems(of app: AXUIElement) -> [AXUIElement] {
        // Menu-bar children are [Apple, App, File, …] in every locale, so the index is stable.
        guard let menuBar = axElement(rawAttribute(of: app, kAXMenuBarAttribute)) else { return [] }
        let menus = children(of: menuBar, attributeName: kAXChildrenAttribute)
        guard menus.count > 2, let fileMenu = children(of: menus[2], attributeName: kAXChildrenAttribute).first else { return [] }
        return children(of: fileMenu, attributeName: kAXChildrenAttribute)
    }

    private static func title(of element: AXUIElement) -> String? {
        rawAttribute(of: element, kAXTitleAttribute) as? String
    }

    private static func windowCount(of app: AXUIElement) -> Int {
        children(of: app, attributeName: kAXWindowsAttribute).count
    }

    private static func children(of element: AXUIElement, attributeName: String) -> [AXUIElement] {
        guard let items = rawAttribute(of: element, attributeName) as? [CFTypeRef] else { return [] }
        return items.compactMap(axElement)
    }

    private static func rawAttribute(of element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func axElement(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // Safe: the CF type id was just verified.
        return (value as! AXUIElement)
    }
}
