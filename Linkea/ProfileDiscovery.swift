import Foundation

/// Result of scanning one browser's profile metadata: what was found, and whether macOS refused
/// to let us look — macOS 27's App Data Protection denies these reads silently unless the user
/// grants Full Disk Access, and the UI must be able to tell that apart from "no profiles".
struct ProfileScan {
    let profiles: [BrowserProfile]
    let accessDenied: Bool

    static let empty = ProfileScan(profiles: [], accessDenied: false)
}

/// Reads browser profile metadata from disk (possible because Linkea is not sandboxed)
/// and delegates all parsing to the pure `ProfileCore`.
enum ProfileDiscovery {
    static func scan(forBundleID bundleID: String) -> ProfileScan {
        if let subpath = ProfileCore.chromiumSupportPath(forBundleID: bundleID) {
            return chromiumProfiles(subpath: subpath, bundleID: bundleID)
        }
        // Firefox and Developer Edition share one profiles.ini.
        if bundleID.hasPrefix("org.mozilla.firefox") {
            return firefoxProfiles(bundleID: bundleID)
        }
        if bundleID == ProfileCore.arcBundleID {
            return arcSpaces(bundleID: bundleID)
        }
        return .empty
    }

    /// True when the failure is macOS refusing access, as opposed to the file being absent or
    /// broken. Walks the underlying-error chain: macOS 27's kernel-level denial can surface as a
    /// generic Cocoa error wrapping the POSIX EPERM.
    static func isPermissionDenial(_ error: any Error) -> Bool {
        var current: NSError? = error as NSError
        while let nsError = current {
            if nsError.domain == NSCocoaErrorDomain, nsError.code == CocoaError.fileReadNoPermission.rawValue {
                return true
            }
            if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(EACCES) || nsError.code == Int(EPERM) {
                return true
            }
            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    private static var applicationSupportURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
    }

    /// Which browser file a log line is about — the read messages stay static across browsers.
    private enum MetadataSource: String {
        case chromiumLocalState = "chromium_local_state"
        case firefoxProfilesINI = "firefox_profiles_ini"
        case arcSidebar = "arc_sidebar"
    }

    private enum MetadataRead {
        case contents(Data)
        /// The scan is already decided — absent, blocked, or unreadable — and was logged.
        case settled(ProfileScan)
    }

    private static func readMetadata(subpath: String, source: MetadataSource, bundleID: String) -> MetadataRead {
        let fields = ["app.bundle_id": bundleID, "profile.source": source.rawValue]
        do {
            return .contents(try Data(contentsOf: applicationSupportURL.appending(path: subpath)))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // Expected for an installed browser that has never run — not an error.
            AppLog.debug("browser profile metadata absent", fields: fields)
            return .settled(.empty)
        } catch where isPermissionDenial(error) {
            // Degraded but recovered: the settings window explains it and links to Full Disk Access.
            AppLog.warn("browser profile metadata blocked by macos", fields: fields)
            return .settled(ProfileScan(profiles: [], accessDenied: true))
        } catch {
            AppLog.error("browser profile metadata read failed", error: error, fields: fields)
            return .settled(.empty)
        }
    }

    private static func chromiumProfiles(subpath: String, bundleID: String) -> ProfileScan {
        let data: Data
        switch readMetadata(subpath: subpath + "/Local State", source: .chromiumLocalState, bundleID: bundleID) {
        case .contents(let contents): data = contents
        case .settled(let scan): return scan
        }
        guard let profiles = ProfileCore.parseChromiumProfiles(localStateJSON: data) else {
            AppLog.warn("chromium local state present but unparseable", fields: ["app.bundle_id": bundleID])
            return .empty
        }
        if profiles.isEmpty {
            AppLog.debug("chromium local state has no user profiles", fields: ["app.bundle_id": bundleID])
        }
        return ProfileScan(profiles: profiles, accessDenied: false)
    }

    private static func firefoxProfiles(bundleID: String) -> ProfileScan {
        let data: Data
        switch readMetadata(subpath: "Firefox/profiles.ini", source: .firefoxProfilesINI, bundleID: bundleID) {
        case .contents(let contents): data = contents
        case .settled(let scan): return scan
        }
        guard let ini = String(data: data, encoding: .utf8) else {
            AppLog.warn("firefox profiles.ini present but not utf-8", fields: ["app.bundle_id": bundleID])
            return .empty
        }
        let profiles = ProfileCore.parseFirefoxProfiles(ini: ini)
        if profiles.isEmpty {
            // The INI parser accepts any text; an empty result just means no profile sections.
            AppLog.debug("firefox profiles.ini has no profiles", fields: ["app.bundle_id": bundleID])
        }
        return ProfileScan(profiles: profiles, accessDenied: false)
    }

    private static func arcSpaces(bundleID: String) -> ProfileScan {
        let data: Data
        switch readMetadata(subpath: ProfileCore.arcSidebarSubpath, source: .arcSidebar, bundleID: bundleID) {
        case .contents(let contents): data = contents
        case .settled(let scan): return scan
        }
        guard let spaces = ProfileCore.parseArcSpaces(sidebarJSON: data) else {
            // Arc's format is undocumented and may change under us; the plain icon still works.
            AppLog.warn("arc sidebar present but unparseable", fields: ["app.bundle_id": bundleID])
            return .empty
        }
        AppLog.debug("arc spaces discovered", fields: ["app.bundle_id": bundleID, "profile.count": String(spaces.count)])
        return ProfileScan(profiles: spaces, accessDenied: false)
    }
}
