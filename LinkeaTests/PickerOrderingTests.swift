import Foundation
import Testing
@testable import Linkea

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
