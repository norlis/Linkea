import Foundation
import Testing
@testable import Linkea

/// Swaps the process-wide `Preferences.defaults` for an isolated suite so no test ever touches
/// the developer's real defaults. Bodies are synchronous and MainActor-isolated, so the swap
/// cannot interleave across tests.
private func withIsolatedDefaults(_ body: () throws -> Void) throws {
    let suiteName = "LinkeaTests-\(UUID().uuidString)"
    let isolated = try #require(UserDefaults(suiteName: suiteName))
    let previous = Preferences.defaults
    Preferences.defaults = isolated
    defer {
        Preferences.defaults = previous
        isolated.removePersistentDomain(forName: suiteName)
    }
    try body()
}

struct PreferencesTests {
    @Test func domainRulesRoundTripThroughUserDefaults() throws {
        try withIsolatedDefaults {
            var rules = LinkRouterCore.DomainRules()
            rules.remember("com.example.browser", for: try #require(URL(string: "https://example.com")))
            Preferences.domainRules = rules
            #expect(Preferences.domainRules == rules)
        }
    }

    /// Pins the recovery contract: one corrupt entry is dropped alone instead of wiping every
    /// pinned site on the next persist.
    @Test func aCorruptStoredValueDropsOnlyItself() throws {
        try withIsolatedDefaults {
            Preferences.defaults.set(
                ["example.com": "com.example.browser", "broken.example": 7],
                forKey: Preferences.Keys.domainRules
            )
            #expect(Preferences.domainRules.storage == ["example.com": "com.example.browser"])
        }
    }

    @Test func onboardingCompletedRoundTrips() throws {
        try withIsolatedDefaults {
            #expect(!Preferences.onboardingCompleted)
            Preferences.onboardingCompleted = true
            #expect(Preferences.onboardingCompleted)
        }
    }

    @Test func safariProfileMenuTitlesRoundTripPreservingOrder() throws {
        try withIsolatedDefaults {
            Preferences.safariProfileMenuTitles = ["New Work Window", "New Personal Window"]
            #expect(Preferences.safariProfileMenuTitles == ["New Work Window", "New Personal Window"])
        }
    }
}

struct RuleStoreTests {
    private let browser = "com.example.browser"

    @Test func rememberPersistsAndSurvivesAReload() throws {
        try withIsolatedDefaults {
            let url = try #require(URL(string: "https://www.example.com/path"))
            let store = RuleStore(rules: Preferences.domainRules)
            store.remember(browser, for: url)
            #expect(store.destination(for: url) == browser)
            let reloaded = RuleStore(rules: Preferences.domainRules)
            #expect(reloaded.destination(for: url) == browser)
        }
    }

    @Test func forgettingAURLRemovesTheRuleFromDisk() throws {
        try withIsolatedDefaults {
            let url = try #require(URL(string: "https://example.com"))
            let store = RuleStore(rules: Preferences.domainRules)
            store.remember(browser, for: url)
            store.forget(for: url)
            #expect(RuleStore(rules: Preferences.domainRules).destination(for: url) == nil)
        }
    }

    @Test func forgettingByHostRemovesOnlyThatSite() throws {
        try withIsolatedDefaults {
            let github = try #require(URL(string: "https://github.com"))
            let apple = try #require(URL(string: "https://apple.com"))
            let store = RuleStore(rules: Preferences.domainRules)
            store.remember(browser, for: github)
            store.remember(browser, for: apple)
            store.forget(host: "github.com")
            let reloaded = RuleStore(rules: Preferences.domainRules)
            #expect(reloaded.destination(for: github) == nil)
            #expect(reloaded.destination(for: apple) == browser)
        }
    }

    @Test func forgettingEverythingClearsDisk() throws {
        try withIsolatedDefaults {
            let url = try #require(URL(string: "https://example.com"))
            let store = RuleStore(rules: Preferences.domainRules)
            store.remember(browser, for: url)
            store.forgetAll()
            #expect(Preferences.domainRules.isEmpty)
        }
    }
}
