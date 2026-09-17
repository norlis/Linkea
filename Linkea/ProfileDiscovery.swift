import Foundation

/// Reads browser profile metadata from disk (possible because Linkea is not sandboxed)
/// and delegates all parsing to the pure `ProfileCore`.
enum ProfileDiscovery {
    static func profiles(forBundleID bundleID: String) -> [BrowserProfile] {
        if let subpath = ProfileCore.chromiumSupportPath(forBundleID: bundleID) {
            return chromiumProfiles(subpath: subpath, bundleID: bundleID)
        }
        // Firefox and Developer Edition share one profiles.ini.
        if bundleID.hasPrefix("org.mozilla.firefox") {
            return firefoxProfiles(bundleID: bundleID)
        }
        return []
    }

    private static var applicationSupportURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
    }

    private static func chromiumProfiles(subpath: String, bundleID: String) -> [BrowserProfile] {
        let localStateURL = applicationSupportURL.appending(path: subpath).appending(path: "Local State")
        let data: Data
        do {
            data = try Data(contentsOf: localStateURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // Expected for an installed browser that has never run — not an error.
            AppLog.debug("no chromium local state present", fields: ["app.bundle_id": bundleID])
            return []
        } catch {
            AppLog.error("chromium local state read failed", error: error, fields: ["app.bundle_id": bundleID])
            return []
        }
        guard let profiles = ProfileCore.parseChromiumProfiles(localStateJSON: data) else {
            AppLog.warn("chromium local state present but unparseable", fields: ["app.bundle_id": bundleID])
            return []
        }
        if profiles.isEmpty {
            AppLog.debug("chromium local state has no user profiles", fields: ["app.bundle_id": bundleID])
        }
        return profiles
    }

    private static func firefoxProfiles(bundleID: String) -> [BrowserProfile] {
        let iniURL = applicationSupportURL.appending(path: "Firefox/profiles.ini")
        let ini: String
        do {
            ini = try String(contentsOf: iniURL, encoding: .utf8)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // Expected when Firefox has never run — not an error.
            AppLog.debug("no firefox profiles.ini present", fields: ["app.bundle_id": bundleID])
            return []
        } catch {
            AppLog.error("firefox profiles.ini read failed", error: error, fields: ["app.bundle_id": bundleID])
            return []
        }
        let profiles = ProfileCore.parseFirefoxProfiles(ini: ini)
        if profiles.isEmpty {
            // The INI parser accepts any text; an empty result just means no profile sections.
            AppLog.debug("firefox profiles.ini has no profiles", fields: ["app.bundle_id": bundleID])
        }
        return profiles
    }
}
