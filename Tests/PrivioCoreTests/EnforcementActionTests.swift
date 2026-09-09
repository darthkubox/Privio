import XCTest
@testable import PrivioCore

/// Atrapa kontrolera aplikacji - zapisuje wywołania hide/activate/terminate.
final class FakeAppController: RunningAppController, @unchecked Sendable {
    private(set) var hidden: [String] = []
    private(set) var activated: [String] = []
    private(set) var terminated: [(String, Bool)] = []
    var running: Set<String> = []
    var frontmost: String?

    private(set) var activatedSelfCount = 0

    func hide(bundleID: String) { hidden.append(bundleID) }
    func activate(bundleID: String) { activated.append(bundleID) }
    func terminate(bundleID: String, force: Bool) { terminated.append((bundleID, force)) }
    func isRunning(bundleID: String) -> Bool { running.contains(bundleID) }
    func frontmostBundleID() -> String? { frontmost }
    func activateSelf() { activatedSelfCount += 1 }
}

final class EnforcementActionTests: XCTestCase {

    private func sampleApp(_ bundle: String = "org.whispersystems.signal-desktop") -> ProtectedApp {
        ProtectedApp(bundleIdentifier: bundle, displayName: "Signal",
                     applicationURL: URL(fileURLWithPath: "/Applications/Signal.app"))
    }

    func testActivatingLockedAppHidesItAndRequestsAuth() async {
        let controller = FakeAppController()
        let service = InProcessEnforcementService(controller: controller)
        await service.addProtectedApp(sampleApp())   // startuje jako .locked

        await service.handle(.activated(bundleID: "org.whispersystems.signal-desktop"))

        let s = await service.currentState()
        XCTAssertEqual(controller.hidden, ["org.whispersystems.signal-desktop"])
        XCTAssertEqual(s.apps[0].status, .authenticating)
        XCTAssertEqual(s.pendingAuthAppID, s.apps[0].id)
    }

    func testActivatingUnlockedAppDoesNothing() async {
        let controller = FakeAppController()
        let service = InProcessEnforcementService(controller: controller)
        await service.addProtectedApp(sampleApp())
        let id = await service.currentState().apps[0].id
        await service.markUnlocked(appID: id)            // teraz .unlocked (activate wywołane)
        controller_activatedReset(controller)

        await service.handle(.activated(bundleID: "org.whispersystems.signal-desktop"))
        let s = await service.currentState()
        XCTAssertEqual(s.apps[0].status, .unlocked)
        XCTAssertTrue(controller.hidden.isEmpty)          // nic nie ukryto
    }

    func testUnprotectedBundleIgnored() async {
        let controller = FakeAppController()
        let service = InProcessEnforcementService(controller: controller)
        await service.addProtectedApp(sampleApp())

        await service.handle(.activated(bundleID: "com.apple.Safari"))  // niechroniona
        let s = await service.currentState()
        XCTAssertTrue(controller.hidden.isEmpty)
        XCTAssertEqual(s.apps[0].status, .locked)
    }

    func testUnlockActivatesApp() async {
        let controller = FakeAppController()
        let service = InProcessEnforcementService(controller: controller)
        await service.addProtectedApp(sampleApp())
        let id = await service.currentState().apps[0].id

        await service.markUnlocked(appID: id)
        XCTAssertEqual(controller.activated, ["org.whispersystems.signal-desktop"])
    }

    func testLockHidesApp() async {
        let controller = FakeAppController()
        let service = InProcessEnforcementService(controller: controller)
        await service.addProtectedApp(sampleApp())
        let id = await service.currentState().apps[0].id
        await service.markUnlocked(appID: id)

        await service.lock(appID: id, reason: .inactivity)
        XCTAssertTrue(controller.hidden.contains("org.whispersystems.signal-desktop"))
        let s = await service.currentState()
        XCTAssertEqual(s.apps[0].status, .locked)
    }

    func testCooldownAfterCancelSuppressesImmediateReprompt() async {
        let clock = TestClock()
        let controller = FakeAppController()
        let auth = FakeAuthenticator(result: .canceled)
        let service = InProcessEnforcementService(controller: controller, authenticator: auth, clock: clock)
        await service.addProtectedApp(sampleApp())
        let id = await service.currentState().apps[0].id

        _ = await service.authenticate(appID: id)   // anulowane → zapisany cooldown
        // Apka wraca natychmiast (w oknie cooldown): tylko ukrycie, bez promptu.
        await service.handle(.activated(bundleID: "org.whispersystems.signal-desktop"))

        let s = await service.currentState()
        XCTAssertEqual(s.apps[0].status, .locked)       // NIE authenticating
        XCTAssertNil(s.pendingAuthAppID)
        XCTAssertGreaterThan(controller.activatedSelfCount, 0)

        // Po upływie cooldown ponowna aktywacja znów prosi o auth.
        clock.advance(by: 1.0)
        await service.handle(.activated(bundleID: "org.whispersystems.signal-desktop"))
        let s2 = await service.currentState()
        XCTAssertEqual(s2.apps[0].status, .authenticating)
    }

    func testCancelAuthReturnsToLocked() async {
        let controller = FakeAppController()
        let service = InProcessEnforcementService(controller: controller)
        await service.addProtectedApp(sampleApp())
        let id = await service.currentState().apps[0].id
        await service.beginAuthentication(appID: id)
        await service.cancelAuthentication(appID: id)

        let s = await service.currentState()
        XCTAssertEqual(s.apps[0].status, .locked)
        XCTAssertNil(s.pendingAuthAppID)
    }

    // Pomocnik: FakeAppController nie ma resetu; tworzymy „świeży" widok przez ignorowanie.
    private func controller_activatedReset(_ c: FakeAppController) { /* no-op: sprawdzamy hidden */ }
}
