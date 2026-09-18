import Foundation
import Testing
@testable import Linkea

@Suite("Rule editor model")
struct RuleEditorModelTests {
    private let bundleID: (RuleDestination) -> String = { $0.browserBundleID }

    private func hostRule(_ name: String, host: String) -> RoutingRule {
        RoutingRule(name: name,
                    matcher: .host(HostMatcher(host: host, includesSubdomains: false)),
                    destination: RuleDestination(browserBundleID: "b", profileID: nil))
    }

    @Test("A pasted URL proposes its host with subdomains off")
    func proposesHost() throws {
        let matcher = try #require(
            RuleEditorModel.proposedMatcher(from: "https://gist.github.com/x/y"))
        guard case .host(let host) = matcher else {
            Issue.record("expected a host matcher")
            return
        }
        #expect(host.host == "gist.github.com")
        #expect(!host.includesSubdomains)
    }

    @Test("Text that is not a URL proposes nothing")
    func proposesNothing() {
        #expect(RuleEditorModel.proposedMatcher(from: "not a url") == nil)
    }

    @Test("The test field says so when the draft wins")
    func draftWins() throws {
        let draft = hostRule("Mail", host: "mail.google.com")
        let table = RuleEditorModel.testTable(
            draft: try RuleCompiler.compile(draft), saved: [])
        let text = RuleEditorModel.testResult(
            for: "https://mail.google.com/u/0", draftID: draft.id, rules: table,
            destinationName: bundleID)
        #expect(text.contains("This rule wins"))
        #expect(text.contains("b"))
    }

    @Test("An earlier saved rule beats the draft and the message names it")
    func earlierRuleWinsFirst() throws {
        let saved = hostRule("Mail", host: "mail.google.com")
        let draft = hostRule("Draft", host: "mail.google.com")
        let table = RuleEditorModel.testTable(
            draft: try RuleCompiler.compile(draft),
            saved: RuleCompiler.compile([saved]))
        let text = RuleEditorModel.testResult(
            for: "https://mail.google.com/u/0", draftID: draft.id, rules: table,
            destinationName: bundleID)
        #expect(text.contains("Mail"))
        #expect(text.contains("wins first"))
    }

    @Test("An edited rule keeps its saved position in the test table")
    func editedRuleKeepsPosition() throws {
        let first = hostRule("First", host: "mail.google.com")
        let second = hostRule("Second", host: "mail.google.com")
        var edited = first
        edited.name = "First edited"
        let table = RuleEditorModel.testTable(
            draft: try RuleCompiler.compile(edited),
            saved: RuleCompiler.compile([first, second]))
        #expect(table.map(\.rule.name) == ["First edited", "Second"])
    }

    @Test("The test field says so when nothing matches")
    func noWinner() {
        let text = RuleEditorModel.testResult(
            for: "https://example.com/", draftID: nil, rules: [], destinationName: bundleID)
        #expect(text.contains("No rule matches"))
    }

    @Test("Invalid test input is reported rather than ignored")
    func invalidInput() {
        let text = RuleEditorModel.testResult(
            for: "not a url", draftID: nil, rules: [], destinationName: bundleID)
        #expect(text.contains("not a URL"))
    }

    @Test("The host explanation names a subdomain and the lookalike it rejects")
    func hostExplanation() {
        let text = RuleEditorModel.hostExplanation(host: "github.com", includesSubdomains: true)
        #expect(text.contains("sub.github.com"))
        #expect(text.contains("notgithub.com"))
        let exact = RuleEditorModel.hostExplanation(host: "github.com", includesSubdomains: false)
        #expect(exact.contains("exactly github.com"))
        #expect(RuleEditorModel.hostExplanation(host: "  ", includesSubdomains: true).isEmpty)
    }
}
