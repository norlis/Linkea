import Foundation
import Testing
@testable import Linkea

struct RuleKeyTests {
    @Test func lowercasesTheHost() throws {
        let url = try #require(URL(string: "HTTPS://GitHub.com/anthropics"))
        #expect(LinkRouterCore.ruleKey(for: url) == "github.com")
    }

    @Test func stripsLeadingWWWSoBothSpellingsShareOneRule() throws {
        let url = try #require(URL(string: "https://www.github.com/anthropics"))
        #expect(LinkRouterCore.ruleKey(for: url) == "github.com")
    }

    @Test func keepsOtherSubdomainsDistinct() throws {
        let url = try #require(URL(string: "https://gist.github.com/x"))
        #expect(LinkRouterCore.ruleKey(for: url) == "gist.github.com")
    }

    @Test func isNilWithoutAHost() throws {
        let url = try #require(URL(string: "https://"))
        #expect(LinkRouterCore.ruleKey(for: url) == nil)
    }

    @Test func aBareWWWHostYieldsNoKeyRatherThanAnEmptyOne() throws {
        let url = try #require(URL(string: "https://www./path"))
        #expect(LinkRouterCore.ruleKey(for: url) == nil)
    }
}

struct DomainRulesTests {
    private let chrome = "com.google.Chrome"
    private let safari = "com.apple.Safari"

    private func url(_ raw: String) throws -> URL {
        try #require(URL(string: raw))
    }

    @Test func hasNoDestinationBeforeAnythingIsRemembered() throws {
        let rules = LinkRouterCore.DomainRules()
        #expect(rules.destination(for: try url("https://github.com")) == nil)
    }

    @Test func remembersABrowserForEverySpellingOfTheSameSite() throws {
        var rules = LinkRouterCore.DomainRules()
        rules.remember(chrome, for: try url("https://github.com/anthropics"))
        #expect(rules.destination(for: try url("https://www.GitHub.com/other/path")) == chrome)
    }

    @Test func doesNotLeakARuleOntoADifferentSite() throws {
        var rules = LinkRouterCore.DomainRules()
        rules.remember(chrome, for: try url("https://github.com"))
        #expect(rules.destination(for: try url("https://gist.github.com")) == nil)
    }

    @Test func rememberingAgainReplacesThePreviousChoice() throws {
        var rules = LinkRouterCore.DomainRules()
        rules.remember(chrome, for: try url("https://github.com"))
        rules.remember(safari, for: try url("https://github.com"))
        #expect(rules.destination(for: try url("https://github.com")) == safari)
    }

    @Test func forgettingRemovesTheRule() throws {
        var rules = LinkRouterCore.DomainRules()
        rules.remember(chrome, for: try url("https://github.com"))
        rules.forget(for: try url("https://github.com"))
        #expect(rules.destination(for: try url("https://github.com")) == nil)
    }

    @Test func isEmptyUntilASiteIsPinned() throws {
        var rules = LinkRouterCore.DomainRules()
        #expect(rules.isEmpty)
        rules.remember(chrome, for: try url("https://github.com"))
        #expect(!rules.isEmpty)
    }

    @Test func listsPinnedSitesSortedByHostSoTheMenuIsStable() throws {
        var rules = LinkRouterCore.DomainRules()
        rules.remember(chrome, for: try url("https://news.ycombinator.com"))
        rules.remember(safari, for: try url("https://apple.com"))
        rules.remember(chrome, for: try url("https://github.com"))
        #expect(rules.entries.map(\.host) == ["apple.com", "github.com", "news.ycombinator.com"])
        #expect(rules.entries.first?.bundleID == safari)
    }

    @Test func forgettingByHostRemovesThatSiteOnly() throws {
        var rules = LinkRouterCore.DomainRules()
        rules.remember(chrome, for: try url("https://github.com"))
        rules.remember(safari, for: try url("https://apple.com"))
        rules.forget(host: "github.com")
        #expect(rules.entries.map(\.host) == ["apple.com"])
    }

    @Test func forgettingEverythingLeavesNoRules() throws {
        var rules = LinkRouterCore.DomainRules()
        rules.remember(chrome, for: try url("https://github.com"))
        rules.remember(safari, for: try url("https://apple.com"))
        rules.forgetAll()
        #expect(rules.isEmpty)
    }

    @Test func roundTripsThroughItsStorageDictionary() throws {
        var rules = LinkRouterCore.DomainRules()
        rules.remember(chrome, for: try url("https://github.com"))
        #expect(LinkRouterCore.DomainRules(storage: rules.storage) == rules)
    }
}

struct PreferredBrowserOrderTests {
    private func candidate(_ bundleID: String) -> LinkRouterCore.BrowserCandidate {
        LinkRouterCore.BrowserCandidate(
            bundleID: bundleID,
            appURL: URL(filePath: "/Applications/\(bundleID).app"),
            displayName: bundleID
        )
    }

    private var installed: [LinkRouterCore.BrowserCandidate] {
        [candidate("com.apple.Safari"), candidate("com.google.Chrome"), candidate("org.mozilla.firefox")]
    }

    @Test func movesTheRememberedBrowserToTheFrontKeepingTheRestInOrder() {
        let ordered = LinkRouterCore.moveToFront(installed, matching: "org.mozilla.firefox", id: \.bundleID)
        #expect(ordered.map(\.bundleID) == ["org.mozilla.firefox", "com.apple.Safari", "com.google.Chrome"])
    }

    @Test func keepsLaunchServicesOrderWhenNothingIsRemembered() {
        #expect(LinkRouterCore.moveToFront(installed, matching: nil, id: \.bundleID) == installed)
    }

    @Test func keepsLaunchServicesOrderWhenTheRememberedBrowserIsGone() {
        #expect(LinkRouterCore.moveToFront(installed, matching: "com.microsoft.edgemac", id: \.bundleID) == installed)
    }
}

struct ShortcutKeyTests {
    @Test(arguments: [("1", 0), ("2", 1), ("9", 8), ("0", 9)])
    func theNumberRowAddressesTheFirstTenPositions(key: String, index: Int) {
        #expect(LinkRouterCore.browserIndex(forShortcutKey: key) == index)
    }

    @Test(arguments: [("q", 10), ("w", 11), ("p", 19)])
    func theQwertyRowTakesOverWhereTheDigitsEnd(key: String, index: Int) {
        #expect(LinkRouterCore.browserIndex(forShortcutKey: key) == index)
    }

    @Test func aShiftedLetterSelectsTheSamePosition() {
        #expect(LinkRouterCore.browserIndex(forShortcutKey: "Q") == 10)
    }

    @Test(arguments: ["a", "z", "s", "", "10", " ", "-"])
    func keysOutsideThoseTwoRowsSelectNothing(key: String) {
        #expect(LinkRouterCore.browserIndex(forShortcutKey: key) == nil)
    }

    @Test(arguments: [(0, "1"), (8, "9"), (9, "0"), (10, "q"), (19, "p")])
    func eachPositionKnowsTheKeyCapToPrint(index: Int, key: String) {
        #expect(LinkRouterCore.shortcutKey(forIndex: index) == key)
    }

    @Test(arguments: [20, 99, -1])
    func positionsOutsideTheTwentySlotsPrintNoKeyCap(index: Int) {
        #expect(LinkRouterCore.shortcutKey(forIndex: index) == nil)
    }

    /// The cap the panel prints and the key the panel listens for must never drift apart.
    @Test func everyPrintedKeyCapSelectsItsOwnPosition() throws {
        for index in 0..<20 {
            let key = try #require(LinkRouterCore.shortcutKey(forIndex: index))
            #expect(LinkRouterCore.browserIndex(forShortcutKey: key) == index)
        }
    }
}
