import XCTest
@testable import PrivioCore

final class LockCoverPolicyTests: XCTestCase {

    private func app(_ bundle: String, protection: Bool = true) -> ProtectedApp {
        ProtectedApp(bundleIdentifier: bundle, displayName: bundle,
                     applicationURL: URL(fileURLWithPath: "/Applications/\(bundle).app"),
                     protectionEnabled: protection)
    }

    private func state(apps: [ProtectedAppSnapshot],
                       protectionActive: Bool = true,
                       appBlockingEnabled: Bool = true) -> EnforcementState {
        var config = AppConfiguration.default
        config.appBlockingEnabled = appBlockingEnabled
        config.protectionActive = protectionActive
        return EnforcementState(protectionActive: protectionActive, apps: apps, configuration: config)
    }

    func testLockedAndAuthenticatingAppsAreCovered() {
        let s = state(apps: [
            ProtectedAppSnapshot(app: app("a.locked"), status: .locked),
            ProtectedAppSnapshot(app: app("b.auth"), status: .authenticating),
        ])
        XCTAssertEqual(LockCoverPolicy.bundleIDsToCover(s), ["a.locked", "b.auth"])
    }

    func testUnlockedAndUnprotectedAppsAreNotCovered() {
        let s = state(apps: [
            ProtectedAppSnapshot(app: app("a.unlocked"), status: .unlocked),
            ProtectedAppSnapshot(app: app("b.off", protection: false), status: .unprotected),
        ])
        XCTAssertTrue(LockCoverPolicy.bundleIDsToCover(s).isEmpty)
    }

    func testGlobalProtectionOffCoversNothing() {
        let s = state(apps: [ProtectedAppSnapshot(app: app("a.locked"), status: .locked)],
                      protectionActive: false)
        XCTAssertTrue(LockCoverPolicy.bundleIDsToCover(s).isEmpty)
    }

    func testAppBlockingModuleOffCoversNothing() {
        let s = state(apps: [ProtectedAppSnapshot(app: app("a.locked"), status: .locked)],
                      appBlockingEnabled: false)
        XCTAssertTrue(LockCoverPolicy.bundleIDsToCover(s).isEmpty)
    }

    /// Apka bez włączonej ochrony, nawet gdy jej ulotny status to `.locked`, nie jest zakrywana.
    func testProtectionDisabledAppNotCoveredEvenIfLocked() {
        let s = state(apps: [ProtectedAppSnapshot(app: app("a", protection: false), status: .locked)])
        XCTAssertTrue(LockCoverPolicy.bundleIDsToCover(s).isEmpty)
    }
}
