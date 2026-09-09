import XCTest
@testable import PrivioCore

/// Ręcznie sterowana atrapa schedulera - test decyduje, kiedy „mija" czas.
final class ManualInactivityScheduler: InactivityScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var scheduled: [String: (TimeInterval, @Sendable () -> Void)] = [:]
    private(set) var canceled: [String] = []

    func schedule(key: String, seconds: TimeInterval, action: @escaping @Sendable () -> Void) {
        lock.lock(); scheduled[key] = (seconds, action); lock.unlock()
    }
    func cancel(key: String) {
        lock.lock(); scheduled[key] = nil; canceled.append(key); lock.unlock()
    }
    func cancelAll() { lock.lock(); scheduled.removeAll(); lock.unlock() }

    var scheduledKeys: [String] { lock.lock(); defer { lock.unlock() }; return Array(scheduled.keys) }
    func seconds(forKey key: String) -> TimeInterval? { lock.lock(); defer { lock.unlock() }; return scheduled[key]?.0 }
    func fire(key: String) {
        lock.lock(); let entry = scheduled[key]; scheduled[key] = nil; lock.unlock()
        entry?.1()
    }
}

final class InactivityTests: XCTestCase {

    private func app(lock: TimeInterval?) -> ProtectedApp {
        ProtectedApp(bundleIdentifier: "org.whispersystems.signal-desktop", displayName: "Signal",
                     applicationURL: URL(fileURLWithPath: "/Applications/Signal.app"),
                     lockAfterInactivity: lock)
    }

    /// Odblokuj apkę i ustaw ją jako foreground (przez zdarzenie aktywacji).
    private func makeUnlockedForeground(lock: TimeInterval?) async
        -> (InProcessEnforcementService, ManualInactivityScheduler, FakeAppController, UUID) {
        let controller = FakeAppController()
        let scheduler = ManualInactivityScheduler()
        let service = InProcessEnforcementService(controller: controller, scheduler: scheduler)
        await service.addProtectedApp(app(lock: lock))
        let id = await service.currentState().apps[0].id
        await service.markUnlocked(appID: id)
        await service.handle(.activated(bundleID: "org.whispersystems.signal-desktop")) // foreground = Signal
        return (service, scheduler, controller, id)
    }

    func testSwitchingAwaySchedulesInactivityLock() async {
        let (service, scheduler, _, id) = await makeUnlockedForeground(lock: 120)
        await service.handle(.activated(bundleID: "com.apple.finder"))   // odejście od Signal
        XCTAssertTrue(scheduler.scheduledKeys.contains("lock-\(id.uuidString)"))
        XCTAssertEqual(scheduler.seconds(forKey: "lock-\(id.uuidString)"), 120)
    }

    func testReturningBeforeTimeoutCancels() async {
        let (service, scheduler, _, id) = await makeUnlockedForeground(lock: 120)
        await service.handle(.activated(bundleID: "com.apple.finder"))   // start odliczania
        await service.handle(.activated(bundleID: "org.whispersystems.signal-desktop")) // powrót
        XCTAssertTrue(scheduler.canceled.contains("lock-\(id.uuidString)"))
        XCTAssertFalse(scheduler.scheduledKeys.contains("lock-\(id.uuidString)"))
    }

    func testImmediateLockWhenTimeoutZero() async {
        let (service, _, controller, _) = await makeUnlockedForeground(lock: 0)
        await service.handle(.activated(bundleID: "com.apple.finder"))
        let s = await service.currentState()
        XCTAssertEqual(s.apps[0].status, .locked)                        // od razu zablokowana
        XCTAssertTrue(controller.hidden.contains("org.whispersystems.signal-desktop"))
    }

    func testNeverTimeoutDoesNotSchedule() async {
        let (service, scheduler, _, _) = await makeUnlockedForeground(lock: nil)
        await service.handle(.activated(bundleID: "com.apple.finder"))
        XCTAssertTrue(scheduler.scheduledKeys.isEmpty)
    }

    func testQuitTimerSchedulesAndTerminates() async {
        let controller = FakeAppController()
        let scheduler = ManualInactivityScheduler()
        let service = InProcessEnforcementService(controller: controller, scheduler: scheduler)
        let a = ProtectedApp(bundleIdentifier: "org.whispersystems.signal-desktop", displayName: "Signal",
                             applicationURL: URL(fileURLWithPath: "/Applications/Signal.app"),
                             lockAfterInactivity: 120, quitAfterInactivity: 900)
        controller.running = ["org.whispersystems.signal-desktop"]
        await service.addProtectedApp(a)
        let id = await service.currentState().apps[0].id
        await service.markUnlocked(appID: id)
        await service.handle(.activated(bundleID: "org.whispersystems.signal-desktop"))  // foreground
        await service.handle(.activated(bundleID: "com.apple.finder"))                   // utrata fokusu

        XCTAssertTrue(scheduler.scheduledKeys.contains("quit-\(id.uuidString)"))
        scheduler.fire(key: "quit-\(id.uuidString)")   // „mija" 900 s

        var terminated = false
        for _ in 0..<50 {
            if controller.terminated.contains(where: { $0.0 == "org.whispersystems.signal-desktop" && !$0.1 }) {
                terminated = true; break
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(terminated)   // łagodne terminate (force=false)
    }

    func testLockedAppLosingFocusStillSchedulesQuit() async {
        let controller = FakeAppController()
        let scheduler = ManualInactivityScheduler()
        let service = InProcessEnforcementService(controller: controller, scheduler: scheduler)
        let a = ProtectedApp(bundleIdentifier: "org.whispersystems.signal-desktop", displayName: "Signal",
                             applicationURL: URL(fileURLWithPath: "/Applications/Signal.app"),
                             lockAfterInactivity: 0, quitAfterInactivity: 60)
        controller.running = [a.bundleIdentifier]
        await service.addProtectedApp(a)
        let id = await service.currentState().apps[0].id

        await service.handle(.activated(bundleID: a.bundleIdentifier))
        await service.handle(.activated(bundleID: "com.apple.finder"))

        XCTAssertTrue(scheduler.scheduledKeys.contains("quit-\(id.uuidString)"))
        XCTAssertEqual(scheduler.seconds(forKey: "quit-\(id.uuidString)"), 60)
    }

    func testChangingQuitTimeoutWhileAppIsInBackgroundReschedulesImmediately() async {
        let controller = FakeAppController()
        let scheduler = ManualInactivityScheduler()
        let service = InProcessEnforcementService(controller: controller, scheduler: scheduler)
        var a = ProtectedApp(bundleIdentifier: "org.whispersystems.signal-desktop", displayName: "Signal",
                             applicationURL: URL(fileURLWithPath: "/Applications/Signal.app"),
                             lockAfterInactivity: 120, quitAfterInactivity: nil)
        controller.running = [a.bundleIdentifier]
        await service.addProtectedApp(a)
        let id = await service.currentState().apps[0].id
        await service.handle(.activated(bundleID: "com.apple.finder"))

        a = await service.currentState().apps[0].app
        a.quitAfterInactivity = 60
        await service.updateProtectedApp(a)

        XCTAssertTrue(scheduler.scheduledKeys.contains("quit-\(id.uuidString)"))
        XCTAssertEqual(scheduler.seconds(forKey: "quit-\(id.uuidString)"), 60)
    }

    func testReturningCancelsQuitTimerToo() async {
        let scheduler = ManualInactivityScheduler()
        let service = InProcessEnforcementService(controller: FakeAppController(), scheduler: scheduler)
        let a = ProtectedApp(bundleIdentifier: "org.whispersystems.signal-desktop", displayName: "Signal",
                             applicationURL: URL(fileURLWithPath: "/Applications/Signal.app"),
                             lockAfterInactivity: 120, quitAfterInactivity: 900)
        await service.addProtectedApp(a)
        let id = await service.currentState().apps[0].id
        await service.markUnlocked(appID: id)
        await service.handle(.activated(bundleID: "org.whispersystems.signal-desktop"))
        await service.handle(.activated(bundleID: "com.apple.finder"))       // start obu timerów
        await service.handle(.activated(bundleID: "org.whispersystems.signal-desktop"))  // powrót

        XCTAssertTrue(scheduler.canceled.contains("quit-\(id.uuidString)"))
        XCTAssertFalse(scheduler.scheduledKeys.contains("quit-\(id.uuidString)"))
    }

    func testFiringTimerLocksApp() async {
        let (service, scheduler, _, id) = await makeUnlockedForeground(lock: 120)
        await service.handle(.activated(bundleID: "com.apple.finder"))
        scheduler.fire(key: "lock-\(id.uuidString)")                     // „mija" 120 s

        // Odpalenie planuje Task na aktorze - poczekaj aż stan się zaktualizuje.
        var status: LockStatus = .unlocked
        for _ in 0..<50 {
            status = await service.currentState().apps[0].status
            if status == .locked { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(status, .locked)
    }
}
