import Foundation
import Testing
@testable import Linkea

@Suite("Rule transfer")
struct RuleTransferTests {
    private func sample(_ name: String, host: String = "example.com",
                        to destination: RuleDestination = RuleDestination(browserBundleID: "com.apple.Safari", profileID: nil)) -> RoutingRule {
        RoutingRule(name: name,
                    matcher: .host(HostMatcher(host: host, includesSubdomains: true)),
                    destination: destination)
    }

    @Test("Export and decode round-trip rules and labels unchanged")
    func roundTrip() throws {
        let rules = [sample("one"), sample("two", host: "b.com")]
        let labels = ["com.apple.Safari": "Safari"]
        let decoded = try RuleTransfer.decode(try RuleTransfer.export(rules, labels: labels))
        #expect(decoded.rules == rules)
        #expect(decoded.destinationLabels == labels)
    }

    @Test("The envelope carries the current format version")
    func envelopeCarriesVersion() throws {
        let data = try RuleTransfer.export([sample("one")], labels: [:])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(RuleTransfer.Archive.self, from: data)
        #expect(archive.version == RuleTransfer.currentVersion)
        #expect(archive.exportedAt != nil)
    }

    @Test("A pre-labels file still decodes, with empty labels")
    func oldFormatDecodes() throws {
        let rule = sample("old")
        let rulesJSON = try #require(String(data: JSONEncoder().encode([rule]), encoding: .utf8))
        let payload = #"{"version": 1, "rules": "# + rulesJSON + "}"
        let decoded = try RuleTransfer.decode(Data(payload.utf8))
        #expect(decoded.rules == [rule])
        #expect(decoded.destinationLabels.isEmpty)
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

    @Test("The label key distinguishes a browser from its profiles")
    func labelKeys() {
        let plain = RuleDestination(browserBundleID: "com.google.Chrome", profileID: nil)
        let profile = RuleDestination(browserBundleID: "com.google.Chrome", profileID: "Profile 2")
        #expect(RuleTransfer.labelKey(for: plain) == "com.google.Chrome")
        #expect(RuleTransfer.labelKey(for: profile) == "com.google.Chrome/Profile 2")
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

@Suite("Import review")
struct ImportReviewAnalysisTests {
    private let missing = RuleDestination(browserBundleID: "com.gone.Browser", profileID: "Work")
    private let present = RuleDestination(browserBundleID: "com.apple.Safari", profileID: nil)

    private func rule(_ name: String, to destination: RuleDestination) -> RoutingRule {
        RoutingRule(name: name,
                    matcher: .host(HostMatcher(host: "example.com", includesSubdomains: true)),
                    destination: destination)
    }

    private func resolvable(_ destination: RuleDestination) -> Bool {
        destination.browserBundleID == "com.apple.Safari"
    }

    @Test("Fully resolvable imports need no review")
    func resolvedNeedsNoReview() {
        let groups = RuleTransfer.analyze([rule("a", to: present)], labels: [:], isResolvable: resolvable)
        #expect(groups.isEmpty)
    }

    @Test("Rules sharing a missing destination land in one group, in first-seen order")
    func groupsByDestination() {
        let other = RuleDestination(browserBundleID: "com.other.Browser", profileID: nil)
        let groups = RuleTransfer.analyze(
            [rule("a", to: missing), rule("b", to: other), rule("c", to: missing)],
            labels: [:], isResolvable: resolvable)
        #expect(groups.map(\.destination) == [missing, other])
        #expect(groups.first?.ruleNames == ["a", "c"])
    }

    @Test("The group label comes from the file, with raw identifiers as fallback")
    func labelsAndFallback() {
        let labeled = RuleTransfer.analyze(
            [rule("a", to: missing)],
            labels: [RuleTransfer.labelKey(for: missing): "Arc — Work"],
            isResolvable: resolvable)
        #expect(labeled.first?.label == "Arc — Work")

        let unlabeled = RuleTransfer.analyze([rule("a", to: missing)], labels: [:], isResolvable: resolvable)
        #expect(unlabeled.first?.label == "com.gone.Browser · Work")
    }

    @Test("Remap rewrites the destination, keep leaves it, skip drops the rule — order preserved")
    func applyResolutions() {
        let kept = RuleDestination(browserBundleID: "com.kept.Browser", profileID: nil)
        let skipped = RuleDestination(browserBundleID: "com.skipped.Browser", profileID: nil)
        let rules = [rule("remap", to: missing), rule("keep", to: kept),
                     rule("skip", to: skipped), rule("untouched", to: present)]
        let result = RuleTransfer.apply(
            [missing: .remap(present), kept: .keep, skipped: .skip],
            to: rules)
        #expect(result.map(\.name) == ["remap", "keep", "untouched"])
        #expect(result.first?.destination == present)
        #expect(result[1].destination == kept)
    }
}
