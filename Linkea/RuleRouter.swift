import Foundation

/// Decides where a set of links should go. Decides only — the caller performs it.
nonisolated enum RuleRouter {
    enum Decision: Hashable, Sendable {
        case route(RuleDestination)
        case ask
    }

    /// Conservative on purpose: partial routing, where some links vanish into a browser
    /// and the rest wait in a panel, would be the surprising option.
    static func resolve(urls: [URL], rules: [CompiledRule],
                        isResolvable: (RuleDestination) -> Bool) -> Decision {
        guard !urls.isEmpty else { return .ask }
        var destinations: Set<RuleDestination> = []
        for url in urls {
            guard let match = RuleTable.firstMatch(for: url, in: rules) else { return .ask }
            destinations.insert(match.rule.destination)
        }
        guard destinations.count == 1, let only = destinations.first, isResolvable(only) else {
            return .ask
        }
        return .route(only)
    }
}
