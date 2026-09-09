import XCTest
@testable import PrivioCore

final class SecurityChangeAssessmentTests: XCTestCase {
    func testDisablingSystemLockTriggersWeakening() {
        let old = AppConfiguration(lockAllAfterScreenLock: true)
        var new = old
        new.lockAllAfterScreenLock = false

        XCTAssertTrue(SecurityChangeAssessment.weakensProtection(from: old, to: new))
    }

    func testShorterDefaultTimeoutDoesNotWeaken() {
        let old = AppConfiguration(defaultLockTimeout: 120)
        var new = old
        new.defaultLockTimeout = 30

        XCTAssertFalse(SecurityChangeAssessment.weakensProtection(from: old, to: new))
    }

    func testNeverDefaultTimeoutWeakensFiniteTimeout() {
        let old = AppConfiguration(defaultLockTimeout: 120)
        var new = old
        new.defaultLockTimeout = nil

        XCTAssertTrue(SecurityChangeAssessment.weakensProtection(from: old, to: new))
    }

    func testAllowingPasswordFallbackWeakensTouchIDOnlyApp() {
        let old = app(allowPasswordFallback: false)
        var new = old
        new.allowPasswordFallback = true

        XCTAssertTrue(SecurityChangeAssessment.weakensProtection(from: old, to: new))
    }

    func testEnablingLockAfterSleepDoesNotWeaken() {
        let old = app(lockAfterSleep: false)
        var new = old
        new.lockAfterSleep = true

        XCTAssertFalse(SecurityChangeAssessment.weakensProtection(from: old, to: new))
    }

    func testUnrelatedMetadataChangeDoesNotWeaken() {
        let old = app()
        var new = old
        new.displayName = "Renamed"

        XCTAssertFalse(SecurityChangeAssessment.weakensProtection(from: old, to: new))
    }

    private func app(lockAfterSleep: Bool = true,
                     allowPasswordFallback: Bool = true) -> ProtectedApp {
        ProtectedApp(
            bundleIdentifier: "com.example.app",
            displayName: "Example",
            applicationURL: URL(fileURLWithPath: "/Applications/Example.app"),
            lockAfterSleep: lockAfterSleep,
            allowPasswordFallback: allowPasswordFallback
        )
    }
}
