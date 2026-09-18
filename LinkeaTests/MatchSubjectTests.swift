import Foundation
import Testing
@testable import Linkea

@Suite("Match subject")
struct MatchSubjectTests {
    @Test("The host subject is lowercased and loses a trailing dot")
    func hostIsNormalized() throws {
        let url = try #require(URL(string: "https://WWW.Example.COM./path"))
        #expect(MatchSubjectResolver.subject(.host, for: url) == "www.example.com")
    }

    @Test("The url subject is the whole lowercased absolute string")
    func urlSubject() throws {
        let url = try #require(URL(string: "https://Example.com/A/B?Q=1"))
        #expect(MatchSubjectResolver.subject(.url, for: url) == "https://example.com/a/b?q=1")
    }

    @Test("A URL with no host yields no host subject")
    func hostlessURL() throws {
        let url = try #require(URL(string: "https:///path"))
        #expect(MatchSubjectResolver.subject(.host, for: url) == nil)
    }

    @Test("A subject longer than the cap is truncated")
    func subjectIsCapped() throws {
        let long = String(repeating: "a", count: MatchSubjectResolver.maxLength + 500)
        let url = try #require(URL(string: "https://example.com/" + long))
        let subject = try #require(MatchSubjectResolver.subject(.url, for: url))
        #expect(subject.count == MatchSubjectResolver.maxLength)
    }
}
