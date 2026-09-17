import Foundation
import Testing
@testable import Linkea

struct PickerKeyActionTests {
    @Test(arguments: [UInt16(36), UInt16(76)])
    func returnAndKeypadEnterOpenTheFirstDestination(keyCode: UInt16) {
        #expect(LinkRouterCore.pickerKeyAction(keyCode: keyCode, characters: nil, isModified: false, destinationCount: 3) == .open(0))
    }

    @Test func aShortcutKeyOpensItsDestination() {
        #expect(LinkRouterCore.pickerKeyAction(keyCode: 20, characters: "3", isModified: false, destinationCount: 5) == .open(2))
    }

    @Test func aModifiedKeystrokeBelongsToTheSystem() {
        #expect(LinkRouterCore.pickerKeyAction(keyCode: 36, characters: nil, isModified: true, destinationCount: 3) == .pass)
    }

    @Test(arguments: ["v", "V"])
    func theLegendKeyTogglesTheLegendCaseInsensitively(key: String) {
        #expect(LinkRouterCore.pickerKeyAction(keyCode: 9, characters: key, isModified: false, destinationCount: 3) == .toggleLegend)
    }

    @Test func aKeyPastTheListPassesThrough() {
        #expect(LinkRouterCore.pickerKeyAction(keyCode: 21, characters: "4", isModified: false, destinationCount: 3) == .pass)
    }

    @Test func aKeyOutsideTheAlphabetPassesThrough() {
        #expect(LinkRouterCore.pickerKeyAction(keyCode: 0, characters: "a", isModified: false, destinationCount: 3) == .pass)
    }

    @Test func withNoDestinationsEverythingPassesThrough() {
        #expect(LinkRouterCore.pickerKeyAction(keyCode: 36, characters: nil, isModified: false, destinationCount: 0) == .pass)
    }

    /// The legend key must never collide with a destination shortcut — asserted here instead of
    /// only in prose.
    @Test func theLegendKeyIsOutsideTheShortcutAlphabet() {
        #expect(!LinkRouterCore.shortcutKeys.contains(LinkRouterCore.legendKey))
    }
}

struct DestinationResolutionTests {
    @Test func aValidDestinationResolvesToItself() {
        let destination = LinkRouterCore.Destination(browser: 1, profile: 1)
        #expect(LinkRouterCore.resolvedDestination(destination, profileCounts: [0, 2]) == destination)
    }

    @Test func aProfilelessDestinationOnlyNeedsItsBrowser() {
        let destination = LinkRouterCore.Destination(browser: 0, profile: nil)
        #expect(LinkRouterCore.resolvedDestination(destination, profileCounts: [0, 2]) == destination)
    }

    @Test func aStaleBrowserIndexResolvesToNothing() {
        #expect(LinkRouterCore.resolvedDestination(LinkRouterCore.Destination(browser: 2, profile: nil), profileCounts: [0, 2]) == nil)
    }

    @Test func aStaleProfileIndexResolvesToNothing() {
        #expect(LinkRouterCore.resolvedDestination(LinkRouterCore.Destination(browser: 1, profile: 2), profileCounts: [0, 2]) == nil)
    }
}

struct LegendPolicyTests {
    @Test func legendListsOnlyProfileDestinationsWithTheirKeys() {
        let legend = LinkRouterCore.legendDestinations(profileCounts: [2, 0, 1])
        #expect(legend.map(\.key) == ["1", "2", "4"])
        #expect(legend.map(\.destination) == [
            LinkRouterCore.Destination(browser: 0, profile: 0),
            LinkRouterCore.Destination(browser: 0, profile: 1),
            LinkRouterCore.Destination(browser: 2, profile: 0)
        ])
    }

    @Test func browsersWithoutProfilesProduceNoLegend() {
        #expect(LinkRouterCore.legendDestinations(profileCounts: [0, 0]).isEmpty)
    }
}

struct ShortcutHintTests {
    @Test func spansTheKeysAndNamesTheReturnTarget() {
        #expect(LinkRouterCore.shortcutHint(destinationCount: 3, firstBrowserName: "Safari", hasLegend: false, legendShown: false) == "1–3 open · return Safari · esc")
    }

    @Test func aSingleDestinationDropsTheSpan() {
        #expect(LinkRouterCore.shortcutHint(destinationCount: 1, firstBrowserName: "Safari", hasLegend: false, legendShown: false) == "1 open · return Safari · esc")
    }

    @Test func theSpanNeverRunsPastTheTwentyKeys() {
        #expect(LinkRouterCore.shortcutHint(destinationCount: 30, firstBrowserName: "Safari", hasLegend: false, legendShown: false) == "1–p open · return Safari · esc")
    }

    @Test func offersTheLegendKeyOnlyWhenThereAreProfiles() {
        #expect(LinkRouterCore.shortcutHint(destinationCount: 3, firstBrowserName: "Chrome", hasLegend: true, legendShown: false) == "1–3 open · return Chrome · v names · esc")
        #expect(LinkRouterCore.shortcutHint(destinationCount: 3, firstBrowserName: "Chrome", hasLegend: true, legendShown: true) == "1–3 open · return Chrome · v hides · esc")
    }

    @Test func withoutBrowsersOnlyEscRemains() {
        #expect(LinkRouterCore.shortcutHint(destinationCount: 0, firstBrowserName: nil, hasLegend: false, legendShown: false) == "esc cancels")
    }
}
