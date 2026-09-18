import Foundation
import Testing
@testable import Linkea

@Suite("Compiled rule")
struct CompiledRuleTests {
    private func rule(_ matcher: RuleMatcher) -> RoutingRule {
        RoutingRule(name: "t", matcher: matcher,
                    destination: RuleDestination(browserBundleID: "com.apple.Safari", profileID: nil))
    }

    @Test("A host rule matches through the compiled wrapper")
    func hostRule() throws {
        let compiled = try RuleCompiler.compile(
            rule(.host(HostMatcher(host: "example.com", includesSubdomains: true))))
        #expect(compiled.matches(try #require(URL(string: "https://a.example.com/x"))))
        #expect(!compiled.matches(try #require(URL(string: "https://other.com/x"))))
    }

    @Test("A regex search is unanchored")
    func unanchored() throws {
        let compiled = try RuleCompiler.compile(
            rule(.regex(RegexMatcher(pattern: "example", subject: .host))))
        #expect(compiled.matches(try #require(URL(string: "https://my.example.com/"))))
    }

    @Test("An anchored regex only matches at the anchor")
    func anchored() throws {
        let compiled = try RuleCompiler.compile(
            rule(.regex(RegexMatcher(pattern: "^example\\.com$", subject: .host))))
        #expect(compiled.matches(try #require(URL(string: "https://example.com/"))))
        #expect(!compiled.matches(try #require(URL(string: "https://my.example.com/"))))
    }

    @Test("Regex matching ignores case")
    func ignoresCase() throws {
        let compiled = try RuleCompiler.compile(
            rule(.regex(RegexMatcher(pattern: "EXAMPLE", subject: .host))))
        #expect(compiled.matches(try #require(URL(string: "https://example.com/"))))
    }

    @Test("A host-subject regex never sees the scheme or the path")
    func hostSubjectIsBare() throws {
        let compiled = try RuleCompiler.compile(
            rule(.regex(RegexMatcher(pattern: "https|/path", subject: .host))))
        #expect(!compiled.matches(try #require(URL(string: "https://example.com/path"))))
    }

    @Test("An uncompilable pattern throws")
    func invalidPatternThrows() {
        #expect(throws: (any Error).self) {
            try RuleCompiler.compile(rule(.regex(RegexMatcher(pattern: "^(a", subject: .host))))
        }
    }

    @Test("Compiling a set keeps the good rules and drops the broken one")
    func compileSetIsLenient() {
        let good = rule(.host(HostMatcher(host: "a.com", includesSubdomains: false)))
        let bad = rule(.regex(RegexMatcher(pattern: "^(a", subject: .host)))
        let compiled = RuleCompiler.compile([good, bad])
        #expect(compiled.count == 1)
        #expect(compiled[0].id == good.id)
    }
}
