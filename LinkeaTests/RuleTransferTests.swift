import Foundation
import Testing
@testable import Linkea

@Suite("Rule transfer")
struct RuleTransferTests {
    private func sample(_ name: String, host: String = "example.com") -> RoutingRule {
        RoutingRule(name: name,
                    matcher: .host(HostMatcher(host: host, includesSubdomains: true)),
                    destination: RuleDestination(browserBundleID: "com.apple.Safari", profileID: nil))
    }

    @Test("Export and decode round-trip the rule set unchanged")
    func roundTrip() throws {
        let rules = [sample("one"), sample("two", host: "b.com")]
        let data = try RuleTransfer.export(rules)
        #expect(try RuleTransfer.decode(data) == rules)
    }

    @Test("The envelope carries the current format version")
    func envelopeCarriesVersion() throws {
        let data = try RuleTransfer.export([sample("one")])
        let archive = try JSONDecoder().decode(RuleTransfer.Archive.self, from: data)
        #expect(archive.version == RuleTransfer.currentVersion)
    }

    @Test("A future format version is rejected, not misread")
    func futureVersionIsRejected() throws {
        let payload = #"{"version": 99, "rules": []}"#
        #expect(throws: RuleTransfer.TransferError.self) {
            try RuleTransfer.decode(Data(payload.utf8))
        }
    }

    @Test("Garbage and envelope-less JSON are malformed", arguments: [
        "{", "not json at all", "[]", #"{"rules": []}"#
    ])
    func malformedIsRejected(payload: String) {
        #expect(throws: RuleTransfer.TransferError.self) {
            try RuleTransfer.decode(Data(payload.utf8))
        }
    }

    @Test("Merge updates a known id in its existing position")
    func mergeUpdatesInPlace() {
        let original = sample("original")
        var edited = original
        edited.name = "edited"
        let merged = RuleTransfer.merge([edited], into: [sample("first"), original])
        #expect(merged.map(\.name) == ["first", "edited"])
    }

    @Test("Merge appends unknown rules at the end in file order")
    func mergeAppendsInOrder() {
        let existing = [sample("existing")]
        let merged = RuleTransfer.merge([sample("a"), sample("b")], into: existing)
        #expect(merged.map(\.name) == ["existing", "a", "b"])
    }

    @Test("Merging the same file twice changes nothing the second time")
    func mergeIsIdempotent() {
        let imported = [sample("a"), sample("b")]
        let once = RuleTransfer.merge(imported, into: [sample("existing")])
        let twice = RuleTransfer.merge(imported, into: once)
        #expect(twice == once)
    }

    @Test("Merging into an empty table keeps the file order")
    func mergeIntoEmpty() {
        let imported = [sample("a"), sample("b")]
        #expect(RuleTransfer.merge(imported, into: []) == imported)
    }
}
