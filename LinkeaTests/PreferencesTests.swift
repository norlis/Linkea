import Foundation
import Testing
@testable import Linkea

struct PreferencesTests {
    @Test func onboardingCompletedRoundTrips() throws {
        try withIsolatedDefaults {
            #expect(!Preferences.onboardingCompleted)
            Preferences.onboardingCompleted = true
            #expect(Preferences.onboardingCompleted)
        }
    }

    @Test func safariProfileMenuTitlesRoundTripPreservingOrder() throws {
        try withIsolatedDefaults {
            Preferences.safariProfileMenuTitles = ["New Work Window", "New Personal Window"]
            #expect(Preferences.safariProfileMenuTitles == ["New Work Window", "New Personal Window"])
        }
    }
}
