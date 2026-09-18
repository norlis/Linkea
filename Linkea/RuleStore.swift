import Foundation
import Observation
// SwiftUI defines Array.move(fromOffsets:toOffset:), the exact mutation List.onMove hands us.
import SwiftUI

/// Observable owner of the route table. Every mutation writes straight through to
/// `Preferences` and rebuilds the compiled table, so the click path never compiles.
@Observable
final class RuleStore {
    private(set) var rules: [RoutingRule]
    private(set) var compiled: [CompiledRule]

    var isPaused: Bool {
        didSet { Preferences.rulesPaused = isPaused }
    }

    init() {
        // The pre-1.x per-host map is gone by owner decision: removed, never migrated or read.
        Preferences.defaults.removeObject(forKey: "domain_rules")
        let stored = Preferences.routingRules
        rules = stored
        compiled = RuleCompiler.compile(stored)
        isPaused = Preferences.rulesPaused
    }

    func add(_ rule: RoutingRule) {
        rules.append(rule)
        persist()
    }

    func update(_ rule: RoutingRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
        persist()
    }

    func remove(id: RoutingRule.ID) {
        rules.removeAll { $0.id == id }
        persist()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        rules.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    /// Merges imported rules in (same id updates in place, new ones append) and returns how many
    /// rows the import actually added or changed, for the confirmation message.
    func importRules(_ imported: [RoutingRule]) -> Int {
        let before = rules
        rules = RuleTransfer.merge(imported, into: rules)
        let added = rules.count - before.count
        let updated = imported.count { rule in
            before.contains { $0.id == rule.id && $0 != rule }
        }
        persist()
        AppLog.info("rules imported", fields: [
            "rule.imported_count": String(imported.count),
            "rule.changed_count": String(added + updated)
        ])
        return added + updated
    }

    private func persist() {
        Preferences.routingRules = rules
        compiled = RuleCompiler.compile(rules)
        AppLog.debug("routing rules updated", fields: ["rule.count": String(rules.count)])
    }
}
