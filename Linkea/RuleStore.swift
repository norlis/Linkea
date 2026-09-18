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

    private func persist() {
        Preferences.routingRules = rules
        compiled = RuleCompiler.compile(rules)
        AppLog.debug("routing rules updated", fields: ["rule.count": String(rules.count)])
    }
}
