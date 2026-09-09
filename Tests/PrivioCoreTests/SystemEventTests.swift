import XCTest
@testable import PrivioCore

final class SystemEventTests: XCTestCase {

    private func app(screenLock: Bool = true, sleep: Bool = true) -> ProtectedApp {
        ProtectedApp(bundleIdentifier: "org.whispersystems.signal-desktop", displayName: "Signal",
                     applicationURL: URL(fileURLWithPath: "/Applications/Signal.app"),
                     lockAfterScreenLock: screenLock, lockAfterSleep: sleep)
    }

    private func unlockedService(app: ProtectedApp) async -> (InProcessEnforcementService, FakeAppController, UUID) {
        let controller = FakeAppController()
        let service = InProcessEnforcementService(controller: controller)
        await service.addProtectedApp(app)
        let id = await service.currentState().apps[0].id
        await service.markUnlocked(appID: id)   // .unlocked
        return (service, controller, id)
    }

    func testScreenLockLocksAndHides() async {
        let (service, controller, _) = await unlockedService(app: app())
        await service.handleSystem(.screenLocked)
        let s = await service.currentState()
        XCTAssertEqual(s.apps[0].status, .locked)
        XCTAssertTrue(controller.hidden.contains("org.whispersystems.signal-desktop"))
        XCTAssertTrue(s.recentActivity.contains { $0.kind == .locked && $0.reason == .screenLock })
    }

    func testSleepLocks() async {
        let (service, _, _) = await unlockedService(app: app())
        await service.handleSystem(.willSleep)
        let s = await service.currentState()
        XCTAssertEqual(s.apps[0].status, .locked)
    }

    func testSessionResignedLocksAll() async {
        let (service, _, _) = await unlockedService(app: app())
        await service.handleSystem(.sessionResigned)
        let s = await service.currentState()
        XCTAssertEqual(s.apps[0].status, .locked)
    }

    func testScreenLockRespectsPerAppFlagOff() async {
        let (service, _, _) = await unlockedService(app: app(screenLock: false))
        await service.handleSystem(.screenLocked)
        let s = await service.currentState()
        XCTAssertEqual(s.apps[0].status, .unlocked)   // pominięte
    }

    func testScreenLockRespectsGlobalToggleOff() async {
        let (service, _, _) = await unlockedService(app: app())
        var config = await service.currentState().configuration
        config.lockAllAfterScreenLock = false
        await service.updateConfiguration(config)
        await service.handleSystem(.screenLocked)
        let s = await service.currentState()
        XCTAssertEqual(s.apps[0].status, .unlocked)   // globalnie wyłączone
    }

    func testWakeDoesNotUnlock() async {
        let (service, _, _) = await unlockedService(app: app())
        await service.handleSystem(.screenLocked)
        await service.handleSystem(.didWake)
        await service.handleSystem(.screenUnlocked)
        let s = await service.currentState()
        XCTAssertEqual(s.apps[0].status, .locked)   // pozostaje zablokowana
    }
}
