import Foundation

/// A rule with its regular expression already built. Compilation happens when the rule
/// set changes, never on the click path.
/// Not `Sendable`: `Regex` is not, and every consumer is `@MainActor` anyway.
nonisolated struct CompiledRule: Identifiable {
    let rule: RoutingRule
    private let regex: Regex<AnyRegexOutput>?

    var id: UUID { rule.id }

    fileprivate init(rule: RoutingRule, regex: Regex<AnyRegexOutput>?) {
        self.rule = rule
        self.regex = regex
    }

    func matches(_ url: URL) -> Bool {
        switch rule.matcher {
        case .host(let matcher):
            guard let host = MatchSubjectResolver.subject(.host, for: url) else { return false }
            return matcher.matches(host)
        case .regex(let matcher):
            guard let regex,
                  let subject = MatchSubjectResolver.subject(matcher.subject, for: url)
            else { return false }
            return (try? regex.firstMatch(in: subject)) != nil
        }
    }
}

nonisolated enum RuleCompiler {
    static func compile(_ rule: RoutingRule) throws -> CompiledRule {
        switch rule.matcher {
        case .host:
            return CompiledRule(rule: rule, regex: nil)
        case .regex(let matcher):
            let regex = try Regex(matcher.pattern).ignoresCase()
            return CompiledRule(rule: rule, regex: regex)
        }
    }

    /// A rule whose pattern no longer compiles is left out and logged, so one bad row
    /// cannot take the whole table down with it.
    static func compile(_ rules: [RoutingRule]) -> [CompiledRule] {
        rules.compactMap { rule in
            do {
                return try compile(rule)
            } catch {
                AppLog.warn("rule failed to compile", fields: ["rule.id": rule.id.uuidString])
                return nil
            }
        }
    }
}

nonisolated enum PatternValidation: Sendable {
    case valid(Duration)
    case invalid(String)
    case tooSlow(Duration)
}

extension RuleCompiler {
    /// A pattern must finish the whole corpus inside this. Measured once, at save time,
    /// in front of the person who can fix it — not on every click, forever.
    static let budget: Duration = .milliseconds(20)

    /// Shapes that make a backtracking engine explode, at the subject cap. The short run with a
    /// failing tail is the ReDoS trigger: `^(a+)+$` needs a match failure to backtrack, and 16
    /// characters already cost ~1.5 s on this engine — far past the budget, still a bounded wait.
    private static let adversarialCorpus: [String] = [
        String(repeating: "a", count: MatchSubjectResolver.maxLength),
        String(repeating: "ab", count: MatchSubjectResolver.maxLength / 2),
        String(repeating: "a", count: 16) + "!",
        String(repeating: "sub.", count: 400) + "example.com",
        "https://example.com/" + String(repeating: "x/", count: 800)
    ]

    static func validate(_ pattern: String) -> PatternValidation {
        guard !pattern.isEmpty else {
            return .invalid("The pattern is empty.")
        }
        let regex: Regex<AnyRegexOutput>
        do {
            regex = try Regex(pattern).ignoresCase()
        } catch {
            return .invalid(error.localizedDescription)
        }
        let elapsed = ContinuousClock().measure {
            for subject in adversarialCorpus {
                _ = try? regex.firstMatch(in: subject)
            }
        }
        return elapsed > budget ? .tooSlow(elapsed) : .valid(elapsed)
    }
}
