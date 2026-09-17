import Foundation

/// Typed access to the app's externalized configuration (the only mutable state that survives
/// a relaunch).
enum Preferences {
    enum Keys {
        static let onboardingCompleted = "onboarding_completed"
        static let safariProfilesEnabled = "safari_profiles_enabled"
        static let safariProfileMenuTitles = "safari_profile_menu_titles"
        static let domainRules = "domain_rules"
    }

    /// Swappable so tests can point the accessors at an isolated suite instead of the user's
    /// real defaults.
    static var defaults: UserDefaults = .standard

    /// Sites the user pinned to a browser, stored as a plist-friendly `[host: bundleID]` map.
    static var domainRules: LinkRouterCore.DomainRules {
        get {
            let raw = defaults.dictionary(forKey: Keys.domainRules) ?? [:]
            // Dropping only the corrupt entries keeps one bad value from erasing every rule on
            // the next persist.
            let stored = raw.compactMapValues { $0 as? String }
            if stored.count < raw.count {
                AppLog.warn("domain rules contained non-string values", fields: ["rule.dropped_count": String(raw.count - stored.count)])
            }
            return LinkRouterCore.DomainRules(storage: stored)
        }
        set { defaults.set(newValue.storage, forKey: Keys.domainRules) }
    }

    static var onboardingCompleted: Bool {
        get { defaults.bool(forKey: Keys.onboardingCompleted) }
        set { defaults.set(newValue, forKey: Keys.onboardingCompleted) }
    }

    static var safariProfilesEnabled: Bool {
        get { defaults.bool(forKey: Keys.safariProfilesEnabled) }
        set { defaults.set(newValue, forKey: Keys.safariProfilesEnabled) }
    }

    /// Exact Safari File-menu item titles the user mapped as profiles, in menu order.
    static var safariProfileMenuTitles: [String] {
        get { defaults.stringArray(forKey: Keys.safariProfileMenuTitles) ?? [] }
        set { defaults.set(newValue, forKey: Keys.safariProfileMenuTitles) }
    }
}
