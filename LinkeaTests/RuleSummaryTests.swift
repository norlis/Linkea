import Testing
@testable import Linkea

@Suite("Rule summary")
struct RuleSummaryTests {
    private func rule(_ matcher: RuleMatcher) -> RoutingRule {
        RoutingRule(name: "n", matcher: matcher,
                    destination: RuleDestination(browserBundleID: "b", profileID: nil))
    }

    @Test("A host rule without subdomains says exact")
    func exactHost() {
        let text = RuleSummary.text(for: rule(
            .host(HostMatcher(host: "example.com", includesSubdomains: false))))
        #expect(text == "example.com exact")
    }

    @Test("A host rule with subdomains says so")
    func withSubdomains() {
        let text = RuleSummary.text(for: rule(
            .host(HostMatcher(host: "example.com", includesSubdomains: true))))
        #expect(text == "example.com and subdomains")
    }

    @Test("A regex rule shows its pattern and subject")
    func regexRule() {
        let text = RuleSummary.text(for: rule(
            .regex(RegexMatcher(pattern: "^a$", subject: .url))))
        #expect(text == "^a$ · full URL")
    }
}
