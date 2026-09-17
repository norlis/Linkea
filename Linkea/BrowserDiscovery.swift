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
        browsers = deduped.map { candidate in
            Browser(
                id: candidate.bundleID,
                name: candidate.displayName,
                appURL: candidate.appURL,
                icon: NSWorkspace.shared.icon(forFile: candidate.appURL.path),
                profiles: profiles(forBundleID: candidate.bundleID)
            )
        }
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

    private func profiles(forBundleID bundleID: String) -> [BrowserProfile] {
        if bundleID == SafariProfileLauncher.safariBundleID {
            return SafariProfileLauncher.configuredProfiles()
        }
        let found = ProfileDiscovery.profiles(forBundleID: bundleID)
        // A single profile adds no choice — the plain icon already opens it.
        return found.count >= 2 ? found : []
    }
}
