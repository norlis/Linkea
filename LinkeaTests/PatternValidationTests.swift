import Foundation
import Testing
@testable import Linkea

@Suite("Pattern validation")
struct PatternValidationTests {
    @Test("A sane pattern is valid and within budget")
    func sanePattern() {
        let result = RuleCompiler.validate("^(mail|calendar)\\.google\\.com$")
        guard case .valid(let elapsed) = result else {
            Issue.record("expected .valid, got \(result)")
            return
        }
        #expect(elapsed < RuleCompiler.budget)
    }

    @Test("An uncompilable pattern is invalid, not slow")
    func invalidPattern() {
        guard case .invalid = RuleCompiler.validate("^(a") else {
            Issue.record("expected .invalid")
            return
        }
    }

    @Test("A catastrophically backtracking pattern is rejected as too slow")
    func catastrophicPattern() {
        guard case .tooSlow = RuleCompiler.validate("^(a+)+$") else {
            Issue.record("expected .tooSlow")
            return
        }
    }

    @Test("An empty pattern is invalid rather than matching everything")
    func emptyPattern() {
        guard case .invalid = RuleCompiler.validate("") else {
            Issue.record("expected .invalid")
            return
        }
    }
}
