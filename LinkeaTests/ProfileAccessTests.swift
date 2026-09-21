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

    @Test("Absence and corruption are not permission denials")
    func nonDenials() {
        #expect(!ProfileDiscovery.isPermissionDenial(CocoaError(.fileReadNoSuchFile)))
        #expect(!ProfileDiscovery.isPermissionDenial(CocoaError(.fileReadCorruptFile)))
    }
}
