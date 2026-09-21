import AppKit
import Observation

/// An installed browser ready to display and launch, with its launchable profiles (if any).
struct Browser: Identifiable, Hashable {
    let id: String
    let name: String
    let appURL: URL
    let icon: NSImage
    let profiles: [BrowserProfile]

    static func == (lhs: Browser, rhs: Browser) -> Bool { lhs.id == rhs.id && lhs.profiles == rhs.profiles }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Thin NSWorkspace adapter around `LinkRouterCore`/`ProfileCore`. The browser list is cached so
/// the picker can render instantly; it refreshes at launch and self-heals after every presentation.
@Observable
final class BrowserDiscovery {
    private(set) var browsers: [Browser] = []
    /// True when macOS refused to let us read some browser's profile metadata (macOS 27 App
    /// Data Protection without Full Disk Access); the settings window explains the remedy.
    private(set) var profileAccessDenied = false

    func refresh() {
        let candidates = NSWorkspace.shared.urlsForApplications(toOpen: LinkRouterCore.probeURL).compactMap { appURL -> LinkRouterCore.BrowserCandidate? in
            guard let bundleID = Bundle(url: appURL)?.bundleIdentifier else { return nil }
            return LinkRouterCore.BrowserCandidate(
                bundleID: bundleID,
                appURL: appURL,
                displayName: FileManager.default.displayName(atPath: appURL.path)
            )
        }
        let deduped = LinkRouterCore.dedupedBrowsers(candidates, excluding: Bundle.main.bundleIdentifier ?? "")
        var accessDenied = false
        browsers = deduped.map { candidate in
            let scan = profileScan(forBundleID: candidate.bundleID)
            accessDenied = accessDenied || scan.accessDenied
            return Browser(
                id: candidate.bundleID,
                name: candidate.displayName,
                appURL: candidate.appURL,
                icon: NSWorkspace.shared.icon(forFile: candidate.appURL.path),
                profiles: scan.profiles
            )
        }
        profileAccessDenied = accessDenied
        AppLog.debug("browser list refreshed", fields: ["browser.count": String(browsers.count)])
    }

    func open(_ urls: [URL], with browser: Browser, profile: BrowserProfile? = nil) {
        guard let profile else {
            openPlain(urls, in: browser)
            return
        }
        switch profile.recipe {
        case .safariProfileMenuItem(let menuTitle):
            SafariProfileLauncher.open(urls, menuItemTitle: menuTitle, safariAppURL: browser.appURL)
        case .chromiumProfileDirectory, .firefoxProfileName:
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = ProfileCore.launchArguments(recipe: profile.recipe, urls: urls)
            // Arguments only reach a fresh process; the browser's singleton forwards them to the
            // running instance when there is one.
            configuration.createsNewApplicationInstance = true
            Task {
                do {
                    _ = try await NSWorkspace.shared.openApplication(at: browser.appURL, configuration: configuration)
                } catch {
                    AppLog.error("browser profile open failed", error: error, fields: ["app.bundle_id": browser.id])
                }
            }
        }
    }

    private func openPlain(_ urls: [URL], in browser: Browser) {
        Task {
            do {
                _ = try await NSWorkspace.shared.open(urls, withApplicationAt: browser.appURL, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                AppLog.error("browser open failed", error: error, fields: ["app.bundle_id": browser.id])
            }
        }
    }

    private func profileScan(forBundleID bundleID: String) -> ProfileScan {
        if bundleID == SafariProfileLauncher.safariBundleID {
            return ProfileScan(profiles: SafariProfileLauncher.configuredProfiles(), accessDenied: false)
        }
        let scan = ProfileDiscovery.scan(forBundleID: bundleID)
        // A single profile adds no choice — the plain icon already opens it.
        return ProfileScan(profiles: scan.profiles.count >= 2 ? scan.profiles : [], accessDenied: scan.accessDenied)
    }
}

extension BrowserDiscovery {
    /// A rule can name a browser the user uninstalled or a profile they deleted.
    func canResolve(_ destination: RuleDestination) -> Bool {
        guard let browser = browsers.first(where: { $0.id == destination.browserBundleID })
        else { return false }
        guard let profileID = destination.profileID else { return true }
        return browser.profiles.contains { $0.id == profileID }
    }

    func open(_ urls: [URL], destination: RuleDestination) {
        guard let browser = browsers.first(where: { $0.id == destination.browserBundleID })
        else { return }
        let profile = destination.profileID.flatMap { id in
            browser.profiles.first { $0.id == id }
        }
        open(urls, with: browser, profile: profile)
    }
}
