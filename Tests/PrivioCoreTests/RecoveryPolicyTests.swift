import XCTest
@testable import PrivioCore

final class RecoveryPolicyTests: XCTestCase {
    private let session = RecoverySession(pid: 123, launchedAt: Date(timeIntervalSince1970: 100))

    func testIdleHelperDoesNotEnableLoginAutostart() {
        var policy = RecoveryPolicy()
        XCTAssertFalse(policy.shouldRelaunch(running: nil, permittedExit: nil, now: 100))
        XCTAssertFalse(policy.shouldRelaunch(running: nil, permittedExit: nil, now: 1_000))
    }

    func testUnexpectedExitRecoversAndRetriesFailedLaunchWithBackoff() {
        var policy = RecoveryPolicy()
        XCTAssertFalse(policy.shouldRelaunch(running: session, permittedExit: nil, now: 100))
        XCTAssertFalse(policy.shouldRelaunch(running: nil, permittedExit: nil, now: 101))
        XCTAssertTrue(policy.shouldRelaunch(running: nil, permittedExit: nil, now: 102))
        XCTAssertFalse(policy.shouldRelaunch(running: nil, permittedExit: nil, now: 103))
        XCTAssertTrue(policy.shouldRelaunch(running: nil, permittedExit: nil, now: 104))
        XCTAssertFalse(policy.shouldRelaunch(running: nil, permittedExit: nil, now: 107))
        XCTAssertTrue(policy.shouldRelaunch(running: nil, permittedExit: nil, now: 108))
    }

    func testGracefulQuitAndUpdateDoNotRelaunch() {
        var policy = RecoveryPolicy()
        XCTAssertFalse(policy.shouldRelaunch(running: session, permittedExit: nil, now: 100))
        XCTAssertFalse(policy.shouldRelaunch(running: nil, permittedExit: session, now: 101))
        XCTAssertFalse(policy.shouldRelaunch(running: nil, permittedExit: session, now: 500))
    }

    func testRepeatedImmediateCrashesKeepBackoff() {
        var policy = RecoveryPolicy()
        _ = policy.shouldRelaunch(running: session, permittedExit: nil, now: 100)
        _ = policy.shouldRelaunch(running: nil, permittedExit: nil, now: 101)
        XCTAssertTrue(policy.shouldRelaunch(running: nil, permittedExit: nil, now: 102))
        let next = RecoverySession(pid: 124, launchedAt: Date(timeIntervalSince1970: 102))
        _ = policy.shouldRelaunch(running: next, permittedExit: nil, now: 102.1)
        _ = policy.shouldRelaunch(running: nil, permittedExit: nil, now: 102.2)
        XCTAssertFalse(policy.shouldRelaunch(running: nil, permittedExit: nil, now: 103))
        XCTAssertTrue(policy.shouldRelaunch(running: nil, permittedExit: nil, now: 104))
    }

    func testNewSessionRearmsAfterGracefulQuitAndRejectsReusedPIDPermit() {
        var policy = RecoveryPolicy()
        _ = policy.shouldRelaunch(running: session, permittedExit: nil, now: 100)
        _ = policy.shouldRelaunch(running: nil, permittedExit: session, now: 101)
        let next = RecoverySession(pid: session.pid, launchedAt: Date(timeIntervalSince1970: 110))
        XCTAssertFalse(policy.shouldRelaunch(running: next, permittedExit: session, now: 110))
        XCTAssertFalse(policy.shouldRelaunch(running: nil, permittedExit: session, now: 111))
        XCTAssertTrue(policy.shouldRelaunch(running: nil, permittedExit: session, now: 112))
    }

    func testManualRelaunchCancelsPendingRecovery() {
        var policy = RecoveryPolicy()
        _ = policy.shouldRelaunch(running: session, permittedExit: nil, now: 100)
        _ = policy.shouldRelaunch(running: nil, permittedExit: nil, now: 101)
        let next = RecoverySession(pid: 124, launchedAt: Date(timeIntervalSince1970: 102))
        XCTAssertFalse(policy.shouldRelaunch(running: next, permittedExit: nil, now: 102))
        XCTAssertFalse(policy.shouldRelaunch(running: nil, permittedExit: next, now: 103))
        XCTAssertFalse(policy.shouldRelaunch(running: nil, permittedExit: next, now: 500))
    }

    func testHeartbeatMustBeRecentAndMatchCurrentProcess() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecoveryStore(directory: directory)
        XCTAssertFalse(store.isWatching(session))
        try store.heartbeat(session: session)
        XCTAssertTrue(store.isWatching(session))
        XCTAssertFalse(store.isWatching(session, now: Date().addingTimeInterval(10)))
        XCTAssertFalse(store.isWatching(RecoverySession(pid: 999, launchedAt: session.launchedAt)))
        try store.permitExit(session)
        XCTAssertEqual(store.permittedExit(), session)
        try Data("corrupted".utf8).write(to: directory.appendingPathComponent("permitted-exit.json"))
        XCTAssertNil(store.permittedExit())
    }
}
