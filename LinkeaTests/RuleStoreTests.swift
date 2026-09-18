import Foundation
import Testing
@testable import Linkea

@Suite("Rule store")
struct RuleStoreTests {
    private func sample(_ name: String, host: String = "example.com") -> RoutingRule {
        RoutingRule(name: name,
                    matcher: .host(HostMatcher(host: host, includesSubdomains: false)),
                    destination: RuleDestination(browserBundleID: "com.apple.Safari", profileID: nil))
    }

    @Test("Adding a rule persists it and survives a reload")
    func addPersists() throws {
        try withIsolatedDefaults {
            let store = RuleStore()
            store.add(sample("one"))
            #expect(RuleStore().rules.map(\.name) == ["one"])
        }
    }

    @Test("The compiled table tracks the rule list")
    func compiledTracksRules() throws {
        try withIsolatedDefaults {
            let store = RuleStore()
            store.add(sample("one"))
            #expect(store.compiled.count == 1)
            store.remove(id: store.rules[0].id)
            #expect(store.compiled.isEmpty)
        }
    }

    @Test("Moving a rule changes precedence and persists")
    func movePersists() throws {
        try withIsolatedDefaults {
            let store = RuleStore()
            store.add(sample("first"))
            store.add(sample("second"))
            store.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
            #expect(RuleStore().rules.map(\.name) == ["second", "first"])
        }
    }

    @Test("Updating a rule replaces it in place")
    func updateInPlace() throws {
        try withIsolatedDefaults {
            let store = RuleStore()
            store.add(sample("one"))
            var edited = store.rules[0]
            edited.name = "renamed"
            store.update(edited)
            #expect(store.rules.map(\.name) == ["renamed"])
        }
    }

    @Test("Importing merges, persists and reports what changed")
    func importPersistsAndCounts() throws {
        try withIsolatedDefaults {
            let store = RuleStore()
            store.add(sample("kept"))
            var edited = store.rules[0]
            edited.name = "renamed"
            let changed = store.importRules([edited, sample("new")])
            #expect(changed == 2)
            #expect(RuleStore().rules.map(\.name) == ["renamed", "new"])
            #expect(store.importRules([edited]) == 0)
        }
    }

    @Test("Initialising the store purges the legacy per-host map")
    func purgesLegacyKey() throws {
        try withIsolatedDefaults {
            Preferences.defaults.set(["example.com": "com.apple.Safari"], forKey: "domain_rules")
            _ = RuleStore()
            #expect(Preferences.defaults.object(forKey: "domain_rules") == nil)
        }
    }
}
