import Foundation

/// Typed access to the app's externalized configuration (the only mutable state that survives
/// a relaunch).
enum Preferences {
    enum Keys {
        static let onboardingCompleted = "onboarding_completed"
        static let safariProfilesEnabled = "safari_profiles_enabled"
        static let safariProfileMenuTitles = "safari_profile_menu_titles"
        static let routingRules = "routing_rules"
        static let rulesPaused = "rules_paused"
        static let hiddenBrowsers = "hidden_browsers"
        static let profiledBrowsers = "profiled_browsers"
        static let accessRepairPending = "access_repair_pending"
    }

    /// Swappable so tests can point the accessors at an isolated suite instead of the user's
    /// real defaults.
    static var defaults: UserDefaults = .standard

    /// Decoding is lenient per rule and strict per field: one corrupt row must not erase a
    /// table the user spent time building.
    private struct LenientRule: Decodable {
        let rule: RoutingRule?

        init(from decoder: any Decoder) throws {
            rule = try? RoutingRule(from: decoder)
        }
    }

    /// The ordered route table, stored as JSON so the closed matcher enum round-trips intact.
    static var routingRules: [RoutingRule] {
        get {
            guard let data = defaults.data(forKey: Keys.routingRules) else { return [] }
            do {
                let rows = try JSONDecoder().decode([LenientRule].self, from: data)
                let rules = rows.compactMap(\.rule)
                if rules.count < rows.count {
                    AppLog.warn("routing rules contained undecodable rows",
                                fields: ["rule.dropped_count": String(rows.count - rules.count)])
                }
                return rules
            } catch {
                AppLog.error("routing rules could not be decoded", error: error)
                return []
            }
        }
        set {
            do {
                defaults.set(try JSONEncoder().encode(newValue), forKey: Keys.routingRules)
            } catch {
                AppLog.error("routing rules could not be encoded", error: error)
            }
        }
    }

    static var rulesPaused: Bool {
        get { defaults.bool(forKey: Keys.rulesPaused) }
        set { defaults.set(newValue, forKey: Keys.rulesPaused) }
    }

    /// Browsers the user unchecked in Settings; the picker skips them. Stored sorted so the
    /// persisted value is stable across writes.
    static var hiddenBrowserBundleIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Keys.hiddenBrowsers) ?? []) }
        set { defaults.set(newValue.sorted(), forKey: Keys.hiddenBrowsers) }
    }

    /// Browsers whose profiles the picker has actually shown, so a later permission denial can
    /// be told apart from "never had profiles". Stored sorted so the persisted value is stable.
    static var profiledBrowserBundleIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Keys.profiledBrowsers) ?? []) }
        set { defaults.set(newValue.sorted(), forKey: Keys.profiledBrowsers) }
    }

    /// Set while a permission repair (reset + relaunch) is in flight, so after the relaunch the
    /// checklist shows approving the consent dialogs as the one remaining step.
    static var accessRepairPending: Bool {
        get { defaults.bool(forKey: Keys.accessRepairPending) }
        set { defaults.set(newValue, forKey: Keys.accessRepairPending) }
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
