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

    private static func chromiumProfiles(subpath: String, bundleID: String) -> ProfileScan {
        let localStateURL = applicationSupportURL.appending(path: subpath).appending(path: "Local State")
        let data: Data
        do {
            data = try Data(contentsOf: localStateURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // Expected for an installed browser that has never run — not an error.
            AppLog.debug("no chromium local state present", fields: ["app.bundle_id": bundleID])
            return .empty
        } catch where isPermissionDenial(error) {
            // Degraded but recovered: the settings window explains it and links to Full Disk Access.
            AppLog.warn("chromium profile data blocked by macos", fields: ["app.bundle_id": bundleID])
            return ProfileScan(profiles: [], accessDenied: true)
        } catch {
            AppLog.error("chromium local state read failed", error: error, fields: ["app.bundle_id": bundleID])
            return .empty
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
        let iniURL = applicationSupportURL.appending(path: "Firefox/profiles.ini")
        let ini: String
        do {
            ini = try String(contentsOf: iniURL, encoding: .utf8)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // Expected when Firefox has never run — not an error.
            AppLog.debug("no firefox profiles.ini present", fields: ["app.bundle_id": bundleID])
            return .empty
        } catch where isPermissionDenial(error) {
            AppLog.warn("firefox profile data blocked by macos", fields: ["app.bundle_id": bundleID])
            return ProfileScan(profiles: [], accessDenied: true)
        } catch {
            AppLog.error("firefox profiles.ini read failed", error: error, fields: ["app.bundle_id": bundleID])
            return .empty
        }
        let profiles = ProfileCore.parseFirefoxProfiles(ini: ini)
        if profiles.isEmpty {
            // The INI parser accepts any text; an empty result just means no profile sections.
            AppLog.debug("firefox profiles.ini has no profiles", fields: ["app.bundle_id": bundleID])
        }
        return ProfileScan(profiles: profiles, accessDenied: false)
    }
}
