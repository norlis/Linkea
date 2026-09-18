import Foundation

/// Which part of a link a regular expression is applied to.
nonisolated enum MatchSubject: String, Codable, Sendable, CaseIterable {
    case host
    case url
}

/// Plain-domain matching. No syntax, therefore no invalid input.
nonisolated struct HostMatcher: Hashable, Codable, Sendable {
    var host: String
    var includesSubdomains: Bool

    /// `normalizedHost` is already lowercased and stripped of a trailing dot.
    func matches(_ normalizedHost: String) -> Bool {
        let pattern = host.lowercased()
        guard !pattern.isEmpty else { return false }
        if normalizedHost == pattern { return true }
        // The leading dot is what stops "notexample.com" matching "example.com".
        return includesSubdomains && normalizedHost.hasSuffix("." + pattern)
    }
}

nonisolated struct RegexMatcher: Hashable, Codable, Sendable {
    var pattern: String
    var subject: MatchSubject
}

/// How a link is recognised. A closed type: the decision point never sees a bare string.
nonisolated enum RuleMatcher: Hashable, Codable, Sendable {
    case host(HostMatcher)
    case regex(RegexMatcher)
}

/// Where a matched link lands. `profileID` is the browser's own identifier.
nonisolated struct RuleDestination: Hashable, Codable, Sendable {
    var browserBundleID: String
    var profileID: String?
}

/// One row of the route table.
nonisolated struct RoutingRule: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var matcher: RuleMatcher
    var destination: RuleDestination
    var isEnabled: Bool

    init(id: UUID = UUID(), name: String, matcher: RuleMatcher,
         destination: RuleDestination, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.matcher = matcher
        self.destination = destination
        self.isEnabled = isEnabled
    }
}

/// Turns a URL into the exact string a matcher is applied to. Bounded on purpose:
/// backtracking cost is a function of subject length.
nonisolated enum MatchSubjectResolver {
    static let maxLength = 2048

    static func normalizeHost(_ host: String) -> String {
        var normalized = host.lowercased()
        if normalized.hasSuffix(".") { normalized.removeLast() }
        return normalized
    }

    static func subject(_ kind: MatchSubject, for url: URL) -> String? {
        let raw: String? = switch kind {
        case .host: url.host().map(normalizeHost)
        case .url: url.absoluteString.lowercased()
        }
        guard let raw, !raw.isEmpty else { return nil }
        guard raw.count > maxLength else { return raw }
        AppLog.warn("match subject truncated", fields: ["subject.length": String(raw.count)])
        return String(raw.prefix(maxLength))
    }
}

/// The route table: ordered, first match wins, evaluation stops there.
nonisolated enum RuleTable {
    static func firstMatch(for url: URL, in rules: [CompiledRule]) -> CompiledRule? {
        rules.first { $0.rule.isEnabled && $0.matches(url) }
    }
}
