import Foundation
import Testing
@testable import Linkea

@Suite("Rule router")
struct RuleRouterTests {
    private let always: (RuleDestination) -> Bool = { _ in true }
    private let never: (RuleDestination) -> Bool = { _ in false }

    private func hostRule(_ host: String, to bundleID: String) -> RoutingRule {
        RoutingRule(name: host,
                    matcher: .host(HostMatcher(host: host, includesSubdomains: true)),
                    destination: RuleDestination(browserBundleID: bundleID, profileID: nil))
    }

    @Test("One matching URL routes to its destination")
    func singleMatch() throws {
        let rules = RuleCompiler.compile([hostRule("example.com", to: "one")])
        let decision = RuleRouter.resolve(
            urls: [try #require(URL(string: "https://example.com/"))],
            rules: rules, isResolvable: always)
        #expect(decision == .route(RuleDestination(browserBundleID: "one", profileID: nil)))
    }

    @Test("Several URLs sharing one destination route together")
    func sharedDestination() throws {
        let rules = RuleCompiler.compile([hostRule("example.com", to: "one")])
        let decision = RuleRouter.resolve(
            urls: [try #require(URL(string: "https://a.example.com/")),
                   try #require(URL(string: "https://b.example.com/"))],
            rules: rules, isResolvable: always)
        #expect(decision == .route(RuleDestination(browserBundleID: "one", profileID: nil)))
    }

    @Test("Several URLs with different destinations fall through to the picker")
    func mixedDestinations() throws {
        let rules = RuleCompiler.compile([
            hostRule("a.com", to: "one"), hostRule("b.com", to: "two")
        ])
        let decision = RuleRouter.resolve(
            urls: [try #require(URL(string: "https://a.com/")),
                   try #require(URL(string: "https://b.com/"))],
            rules: rules, isResolvable: always)
        #expect(decision == .ask)
    }

    @Test("One unmatched URL in the set falls through for all of them")
    func partialMatchAsks() throws {
        let rules = RuleCompiler.compile([hostRule("a.com", to: "one")])
        let decision = RuleRouter.resolve(
            urls: [try #require(URL(string: "https://a.com/")),
                   try #require(URL(string: "https://unmatched.com/"))],
            rules: rules, isResolvable: always)
        #expect(decision == .ask)
    }

    @Test("An unresolvable destination falls through instead of substituting a browser")
    func unresolvableDestination() throws {
        let rules = RuleCompiler.compile([hostRule("example.com", to: "gone")])
        let decision = RuleRouter.resolve(
            urls: [try #require(URL(string: "https://example.com/"))],
            rules: rules, isResolvable: never)
        #expect(decision == .ask)
    }

    @Test("No URLs asks")
    func noURLs() {
        #expect(RuleRouter.resolve(urls: [], rules: [], isResolvable: always) == .ask)
    }
}
