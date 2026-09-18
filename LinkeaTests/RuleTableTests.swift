import Foundation
import Testing
@testable import Linkea

@Suite("Rule table")
struct RuleTableTests {
    private func hostRule(_ host: String, to bundleID: String, enabled: Bool = true) -> RoutingRule {
        RoutingRule(name: host,
                    matcher: .host(HostMatcher(host: host, includesSubdomains: true)),
                    destination: RuleDestination(browserBundleID: bundleID, profileID: nil),
                    isEnabled: enabled)
    }

    @Test("The first matching rule wins")
    func firstWins() throws {
        let rules = RuleCompiler.compile([
            hostRule("example.com", to: "one"),
            hostRule("example.com", to: "two")
        ])
        let url = try #require(URL(string: "https://example.com/"))
        let match = try #require(RuleTable.firstMatch(for: url, in: rules))
        #expect(match.rule.destination.browserBundleID == "one")
    }

    @Test("Reordering flips the winner")
    func orderIsPrecedence() throws {
        let rules = RuleCompiler.compile([
            hostRule("example.com", to: "two"),
            hostRule("example.com", to: "one")
        ])
        let url = try #require(URL(string: "https://example.com/"))
        let match = try #require(RuleTable.firstMatch(for: url, in: rules))
        #expect(match.rule.destination.browserBundleID == "two")
    }

    @Test("A disabled rule is skipped even when it would match")
    func disabledIsSkipped() throws {
        let rules = RuleCompiler.compile([
            hostRule("example.com", to: "off", enabled: false),
            hostRule("example.com", to: "on")
        ])
        let url = try #require(URL(string: "https://example.com/"))
        let match = try #require(RuleTable.firstMatch(for: url, in: rules))
        #expect(match.rule.destination.browserBundleID == "on")
    }

    @Test("No rule matches an unrelated host")
    func noMatch() throws {
        let rules = RuleCompiler.compile([hostRule("example.com", to: "one")])
        let url = try #require(URL(string: "https://other.com/"))
        #expect(RuleTable.firstMatch(for: url, in: rules) == nil)
    }

    @Test("An empty table matches nothing")
    func emptyTable() throws {
        let url = try #require(URL(string: "https://example.com/"))
        #expect(RuleTable.firstMatch(for: url, in: []) == nil)
    }
}
