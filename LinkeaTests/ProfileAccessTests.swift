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
