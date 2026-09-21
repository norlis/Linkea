import Testing
@testable import Linkea

@Suite("Permission reset")
struct PermissionResetTests {
    @Test("The scoped service is tried before the blanket reset")
    func scopedBeforeAll() {
        let commands = PermissionReset.commands(bundleID: "com.example.app")
        #expect(commands.count == 2)
        #expect(commands.first == ["/usr/bin/tccutil", "reset", "SystemPolicyAppDataDetailed", "com.example.app"])
        #expect(commands.last == ["/usr/bin/tccutil", "reset", "All", "com.example.app"])
    }

    @Test("An empty bundle id produces no commands rather than a blanket reset")
    func emptyBundleID() {
        #expect(PermissionReset.commands(bundleID: "").isEmpty)
    }
}

@Suite("Setup requirements")
struct SetupRequirementsTests {
    @Test("A denial needs action even though it also reports zero profiles")
    func denialWins() {
        #expect(SetupRequirements.profileDataStatus(accessDenied: true, browsersWithProfiles: 0) == .actionNeeded)
    }

    @Test("Readable profiles satisfy the requirement")
    func satisfied() {
        #expect(SetupRequirements.profileDataStatus(accessDenied: false, browsersWithProfiles: 2) == .satisfied)
    }

    @Test("No multi-profile browsers means the row does not apply")
    func notApplicable() {
        #expect(SetupRequirements.profileDataStatus(accessDenied: false, browsersWithProfiles: 0) == .notApplicable)
    }
}
