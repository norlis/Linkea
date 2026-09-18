import Foundation
import Testing
@testable import Linkea

@Suite("Rule persistence")
struct RulePersistenceTests {
    private func sample(_ name: String) -> RoutingRule {
        RoutingRule(name: name,
                    matcher: .host(HostMatcher(host: "example.com", includesSubdomains: true)),
                    destination: RuleDestination(browserBundleID: "com.apple.Safari", profileID: "Work"))
    }

    @Test("A rule set round-trips unchanged")
    func roundTrip() throws {
        try withIsolatedDefaults {
            let rules = [sample("one"), sample("two")]
            Preferences.routingRules = rules
            #expect(Preferences.routingRules == rules)
        }
    }

    @Test("No stored value yields an empty table, not a crash")
    func emptyByDefault() throws {
        try withIsolatedDefaults {
            #expect(Preferences.routingRules.isEmpty)
        }
    }

    @Test("One corrupt row is dropped and the rest survive")
    func corruptRowIsDropped() throws {
        try withIsolatedDefaults {
            let good = try JSONEncoder().encode(sample("good"))
            let goodObject = try #require(String(data: good, encoding: .utf8))
            let payload = "[\(goodObject),{\"nonsense\":true}]"
            Preferences.defaults.set(Data(payload.utf8), forKey: Preferences.Keys.routingRules)

            let loaded = Preferences.routingRules
            #expect(loaded.count == 1)
            #expect(loaded.first?.name == "good")
        }
    }

    @Test("The paused flag round-trips and defaults to false")
    func pausedFlag() throws {
        try withIsolatedDefaults {
            #expect(Preferences.rulesPaused == false)
            Preferences.rulesPaused = true
            #expect(Preferences.rulesPaused)
        }
    }
}
