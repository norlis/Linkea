import Foundation
import Testing
@testable import Linkea

@Suite("Profile access denial")
struct ProfileAccessTests {
    @Test("Permission errors are recognised as macOS blocking access")
    func permissionDenials() {
        #expect(ProfileDiscovery.isPermissionDenial(CocoaError(.fileReadNoPermission)))
        #expect(ProfileDiscovery.isPermissionDenial(NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))))
        #expect(ProfileDiscovery.isPermissionDenial(NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))))
    }

    @Test("A denial buried as an underlying error is still recognised")
    func wrappedDenials() {
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadUnknown.rawValue,
                              userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))])
        #expect(ProfileDiscovery.isPermissionDenial(wrapped))
    }

    @Test("Absence and corruption are not permission denials")
    func nonDenials() {
        #expect(!ProfileDiscovery.isPermissionDenial(CocoaError(.fileReadNoSuchFile)))
        #expect(!ProfileDiscovery.isPermissionDenial(CocoaError(.fileReadCorruptFile)))
    }
}

@Suite("Profile access regression")
struct ProfileAccessRegressionTests {
    private let chrome = "com.google.Chrome"
    private let firefox = "org.mozilla.firefox"

    @Test("A denial for a browser that showed profiles raises the notice")
    func regressionRaisesNotice() {
        let assessment = ProfileAccessTracker.assess(
            previouslyProfiled: [chrome],
            outcomes: [ProfileScanOutcome(bundleID: chrome, hasProfiles: false, accessDenied: true)])
        #expect(assessment.showsBlockedNotice)
    }

    @Test("A first-run denial with no history stays quiet")
    func firstRunDenialStaysQuiet() {
        let assessment = ProfileAccessTracker.assess(
            previouslyProfiled: [],
            outcomes: [ProfileScanOutcome(bundleID: chrome, hasProfiles: false, accessDenied: true)])
        #expect(!assessment.showsBlockedNotice)
        #expect(assessment.knownProfiledBundleIDs.isEmpty)
    }

    @Test("A clean scan records which browsers have profiles")
    func cleanScanRecordsProfiles() {
        let assessment = ProfileAccessTracker.assess(
            previouslyProfiled: [],
            outcomes: [
                ProfileScanOutcome(bundleID: chrome, hasProfiles: true, accessDenied: false),
                ProfileScanOutcome(bundleID: firefox, hasProfiles: false, accessDenied: false)
            ])
        #expect(!assessment.showsBlockedNotice)
        #expect(assessment.knownProfiledBundleIDs == [chrome])
    }

    @Test("Cleanly losing all profiles forgets the browser instead of warning later")
    func cleanEmptyScanForgets() {
        let assessment = ProfileAccessTracker.assess(
            previouslyProfiled: [chrome],
            outcomes: [ProfileScanOutcome(bundleID: chrome, hasProfiles: false, accessDenied: false)])
        #expect(!assessment.showsBlockedNotice)
        #expect(assessment.knownProfiledBundleIDs.isEmpty)
    }

    @Test("A denial keeps the browser known so the notice survives relaunches")
    func denialPreservesKnowledge() {
        let assessment = ProfileAccessTracker.assess(
            previouslyProfiled: [chrome],
            outcomes: [ProfileScanOutcome(bundleID: chrome, hasProfiles: false, accessDenied: true)])
        #expect(assessment.knownProfiledBundleIDs == [chrome])
    }

    @Test("One denied browser does not hide another browser's healthy profiles")
    func mixedScanBothTracksAndWarns() {
        let assessment = ProfileAccessTracker.assess(
            previouslyProfiled: [chrome],
            outcomes: [
                ProfileScanOutcome(bundleID: chrome, hasProfiles: false, accessDenied: true),
                ProfileScanOutcome(bundleID: firefox, hasProfiles: true, accessDenied: false)
            ])
        #expect(assessment.showsBlockedNotice)
        #expect(assessment.knownProfiledBundleIDs == [chrome, firefox])
    }
}

@Suite("Profile access guide")
struct ProfileAccessGuideTests {
    @Test("Granted access is done regardless of history")
    func grantedIsDone() {
        #expect(ProfileAccessGuide.step(
            accessDenied: false, regressed: true, requestAttempted: true, repairPending: true) == .done)
    }

    @Test("A fresh denial starts with a plain request")
    func freshDenialRequests() {
        #expect(ProfileAccessGuide.step(
            accessDenied: true, regressed: false, requestAttempted: false, repairPending: false) == .request)
    }

    @Test("A regression goes straight to repair — macOS never re-prompts over a stale record")
    func regressionRepairs() {
        #expect(ProfileAccessGuide.step(
            accessDenied: true, regressed: true, requestAttempted: false, repairPending: false) == .repair)
    }

    @Test("A request that changed nothing escalates to repair")
    func failedRequestEscalates() {
        #expect(ProfileAccessGuide.step(
            accessDenied: true, regressed: false, requestAttempted: true, repairPending: false) == .repair)
    }

    @Test("Right after a repair relaunch the only step left is approving the dialogs")
    func repairPendingAsksForApproval() {
        #expect(ProfileAccessGuide.step(
            accessDenied: true, regressed: true, requestAttempted: false, repairPending: true) == .approvePrompts)
    }
}
