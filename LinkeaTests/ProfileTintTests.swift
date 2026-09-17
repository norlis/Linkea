import Foundation
import Testing
@testable import Linkea

struct ProfileTintTests {
    /// The two values below are the ones Chrome actually wrote for the profiles on this machine.
    @Test(arguments: [
        (-12689768, ProfileTint(red: 0x3E, green: 0x5E, blue: 0x98)),
        (-7059392, ProfileTint(red: 0x94, green: 0x48, blue: 0x40))
    ])
    func decodesChromiumsSignedARGBIntoComponents(stored: Int, expected: ProfileTint) {
        #expect(ProfileCore.tint(fromChromiumColor: stored) == expected)
    }

    @Test func opaqueWhiteAndBlackSurviveTheSignedRoundTrip() {
        #expect(ProfileCore.tint(fromChromiumColor: -1) == ProfileTint(red: 255, green: 255, blue: 255))
        #expect(ProfileCore.tint(fromChromiumColor: -16777216) == ProfileTint(red: 0, green: 0, blue: 0))
    }

    @Test func aDarkTintAsksForLightText() {
        #expect(ProfileTint(red: 0x3E, green: 0x5E, blue: 0x98).prefersLightForeground)
    }

    @Test func aPaleTintAsksForDarkText() {
        // Chrome's untouched default is this near-grey; a white digit on it is unreadable.
        #expect(!ProfileTint(red: 0xA7, green: 0xAB, blue: 0xB7).prefersLightForeground)
    }

    @Test func alphaIsDiscardedRatherThanBleedingIntoRed() {
        // 0x80FF0000 — half-transparent red. The panel always draws the dot opaque.
        #expect(ProfileCore.tint(fromChromiumColor: -2130771968) == ProfileTint(red: 255, green: 0, blue: 0))
    }
}

struct ChromiumProfileColorTests {
    private func fixture(_ profileBody: String) -> Data {
        Data(#"{ "profile": { "info_cache": { "Default": \#(profileBody) } } }"#.utf8)
    }

    @Test func aProfileCarriesTheSeedColorChromeAssignedIt() throws {
        let profiles = try #require(ProfileCore.parseChromiumProfiles(
            localStateJSON: fixture(#"{ "name": "Tu Chrome", "profile_color_seed": -12689768 }"#)
        ))
        #expect(profiles.first?.tint == ProfileTint(red: 0x3E, green: 0x5E, blue: 0x98))
    }

    @Test func theHighlightColorStandsInWhenThereIsNoSeed() throws {
        let profiles = try #require(ProfileCore.parseChromiumProfiles(
            localStateJSON: fixture(#"{ "name": "Trabajo", "profile_highlight_color": -7059392 }"#)
        ))
        #expect(profiles.first?.tint == ProfileTint(red: 0x94, green: 0x48, blue: 0x40))
    }

    @Test func theSeedWinsOverTheHighlightWhenBothArePresent() throws {
        let profiles = try #require(ProfileCore.parseChromiumProfiles(
            localStateJSON: fixture(#"{ "name": "Ambos", "profile_color_seed": -12689768, "profile_highlight_color": -7059392 }"#)
        ))
        #expect(profiles.first?.tint == ProfileTint(red: 0x3E, green: 0x5E, blue: 0x98))
    }

    @Test func aProfileWithoutAnyColorHasNoTint() throws {
        let profiles = try #require(ProfileCore.parseChromiumProfiles(localStateJSON: fixture(#"{ "name": "Gris" }"#)))
        #expect(profiles.first?.tint == nil)
    }

    @Test func firefoxProfilesHaveNoTintBecauseTheINIHasNoColor() {
        let profiles = ProfileCore.parseFirefoxProfiles(ini: "[Profile0]\nName=default-release\n")
        #expect(profiles.first?.tint == nil)
    }
}

struct DestinationListTests {
    private func destination(_ browser: Int, _ profile: Int?) -> LinkRouterCore.Destination {
        LinkRouterCore.Destination(browser: browser, profile: profile)
    }

    @Test func aBrowserWithProfilesHandsItsSlotsToThem() {
        #expect(LinkRouterCore.destinations(profileCounts: [2, 0]) == [
            destination(0, 0), destination(0, 1), destination(1, nil)
        ])
    }

    @Test func aBrowserWithoutProfilesKeepsTheSlotForItself() {
        #expect(LinkRouterCore.destinations(profileCounts: [0, 0]) == [
            destination(0, nil), destination(1, nil)
        ])
    }

    @Test func profilesOfDifferentBrowsersInterleaveInBrowserOrder() {
        #expect(LinkRouterCore.destinations(profileCounts: [1, 0, 2]) == [
            destination(0, 0), destination(1, nil), destination(2, 0), destination(2, 1)
        ])
    }

    @Test func noBrowsersMeansNoDestinations() {
        #expect(LinkRouterCore.destinations(profileCounts: []).isEmpty)
    }
}
