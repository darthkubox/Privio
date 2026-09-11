import XCTest
@testable import PrivioCore

@MainActor
final class TerminationCoordinatorTests: XCTestCase {
    func testCancelledOrFailedAuthenticationDoesNotCleanUpOrTerminate() async {
        let coordinator = TerminationCoordinator()
        var cleanupCalled = false
        var terminateCalled = false
        let task = coordinator.request(authorize: { false }, prepare: {
            cleanupCalled = true
            return true
        }, terminate: { terminateCalled = true })
        await task?.value
        XCTAssertFalse(cleanupCalled)
        XCTAssertFalse(terminateCalled)
        XCTAssertFalse(coordinator.isTerminationAuthorized)
        XCTAssertFalse(coordinator.isPreparing)
    }

    func testAuthorizationPrecedesVaultAndIsValidOnlyInsideTerminationRetry() async {
        let coordinator = TerminationCoordinator()
        var calls: [String] = []
        let task = coordinator.request(authorize: {
            XCTAssertFalse(coordinator.isTerminationAuthorized)
            calls.append("authenticate")
            return true
        }, prepare: {
            XCTAssertFalse(coordinator.isTerminationAuthorized)
            calls.append("vault")
            return true
        }, terminate: {
            XCTAssertTrue(coordinator.isTerminationAuthorized)
            calls.append("terminate")
        })
        await task?.value
        XCTAssertEqual(calls, ["authenticate", "vault", "terminate"])
        // Also covers an AppKit retry that returned without exiting (e.g. cancel).
        XCTAssertFalse(coordinator.isTerminationAuthorized)
        XCTAssertFalse(coordinator.isPreparing)
    }

    func testVaultFailureRevokesApprovalAndNextQuitAuthenticatesAgain() async {
        let coordinator = TerminationCoordinator()
        var authentications = 0
        var terminations = 0
        let authorize: @MainActor () async -> Bool = { authentications += 1; return true }
        let first = coordinator.request(authorize: authorize, prepare: { false },
                                        terminate: { terminations += 1 })
        await first?.value
        XCTAssertEqual(terminations, 0)
        XCTAssertFalse(coordinator.isTerminationAuthorized)
        let second = coordinator.request(authorize: authorize, prepare: { true },
                                         terminate: { terminations += 1 })
        await second?.value
        XCTAssertEqual(authentications, 2)
        XCTAssertEqual(terminations, 1)
    }

    func testRepeatedQuitRequestsDoNotCreateParallelPromptsOrSkipAuth() async {
        let coordinator = TerminationCoordinator()
        var authentications = 0
        let first = coordinator.request(authorize: { authentications += 1; return false },
                                        prepare: { XCTFail("Unauthorized cleanup"); return true },
                                        terminate: { XCTFail("Unauthorized exit") })
        let second = coordinator.request(authorize: { XCTFail("Parallel prompt"); return true },
                                         prepare: { true }, terminate: { XCTFail("Parallel exit") })
        XCTAssertNil(second)
        await first?.value
        XCTAssertEqual(authentications, 1)
    }

    func testCancelledTaskCannotTerminateAfterAuthenticationReturnsSuccess() async {
        let coordinator = TerminationCoordinator()
        let task = coordinator.request(authorize: { true }, prepare: { true },
                                       terminate: { XCTFail("Cancelled request exited") })
        task?.cancel()
        await task?.value
        XCTAssertFalse(coordinator.isTerminationAuthorized)
        XCTAssertFalse(coordinator.isPreparing)
    }
}
