import Testing
@testable import Linkea

@Suite("Host matcher")
struct HostMatcherTests {
    @Test("An exact host matches and a different one does not")
    func exactHost() {
        let matcher = HostMatcher(host: "example.com", includesSubdomains: false)
        #expect(matcher.matches("example.com"))
        #expect(!matcher.matches("other.com"))
    }

    @Test("With subdomains off, www is a different host")
    func subdomainsOff() {
        let matcher = HostMatcher(host: "example.com", includesSubdomains: false)
        #expect(!matcher.matches("www.example.com"))
    }

    @Test("With subdomains on, every depth matches", arguments: [
        "example.com", "www.example.com", "a.b.example.com"
    ])
    func subdomainsOn(host: String) {
        let matcher = HostMatcher(host: "example.com", includesSubdomains: true)
        #expect(matcher.matches(host))
    }

    @Test("The boundary dot stops a lookalike domain")
    func lookalikeIsRejected() {
        let matcher = HostMatcher(host: "example.com", includesSubdomains: true)
        #expect(!matcher.matches("notexample.com"))
    }

    @Test("An empty pattern never matches")
    func emptyPattern() {
        let matcher = HostMatcher(host: "", includesSubdomains: true)
        #expect(!matcher.matches("example.com"))
    }
}
