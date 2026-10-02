import XCTest
@testable import PrivioCore

/// Atrapa autentykatora - zwraca zaprogramowany wynik bez systemowego promptu.
final class FakeAuthenticator: BiometricAuthenticating, @unchecked Sendable {
    var result: AuthResult
    private(set) var calls: [(bundleID: String, policy: AuthPolicy)] = []

    init(result: AuthResult) { self.result = result }

    func authenticate(bundleID: String, appName: String, policy: AuthPolicy) async -> AuthResult {
        calls.append((bundleID, policy))
        return result
    }

    func authenticate(reason: String, policy: AuthPolicy) async -> AuthResult { result }
}

final class FakeFailedAttemptRecorder: FailedAttemptRecording, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedBundleIDs: [String] = []

    func recordFailedAttempt(bundleID: String, appName: String) async -> String? {
        lock.withLock { recordedBundleIDs.append(bundleID) }
        return "failed-attempt.jpg"
    }

    var count: Int { lock.withLock { recordedBundleIDs.count } }
}

/// Atrapa z promptem „w toku": każde wywołanie czeka, aż test je rozstrzygnie.
final class PendingAuthenticator: BiometricAuthenticating, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [CheckedContinuation<AuthResult, Never>] = []

    func authenticate(bundleID: String, appName: String, policy: AuthPolicy) async -> AuthResult {
        await withCheckedContinuation { c in lock.withLock { pending.append(c) } }
    }

    func authenticate(reason: String, policy: AuthPolicy) async -> AuthResult { .success }

    var count: Int { lock.withLock { pending.count } }
    func resolve(_ index: Int, with result: AuthResult) { lock.withLock { pending[index] }.resume(returning: result) }
}

final class AuthFlowTests: XCTestCase {

    func testSupersededPromptIsNotRecordedAsFailure() async {
        // Prompt zgubił się pod oknami → „Unlock" na zasłonie wywołuje nowy; stary
        // kończy się `.canceled` (invalidate) i NIE może liczyć się jako nieudana próba.
        let controller = FakeAppController()
        let auth = PendingAuthenticator()
        let recorder = FakeFailedAttemptRecorder()
        let service = InProcessEnforcementService(controller: controller, authenticator: auth,
                                                  failedAttemptRecorder: recorder)
        await service.addProtectedApp(sampleApp())
        var config = await service.currentState().configuration
        config.captureFailedAttempts = true
        await service.updateConfiguration(config)
        let id = await service.currentState().apps[0].id

        let first = Task { await service.authenticate(appID: id) }
        while auth.count < 1 { await Task.yield() }
        let second = Task { await service.authenticate(appID: id) }
        while auth.count < 2 { await Task.yield() }

        auth.resolve(0, with: .canceled)            // zastąpiony prompt
        let firstResult = await first.value
        XCTAssertFalse(firstResult)
        var s = await service.currentState()
        XCTAssertEqual(s.apps[0].status, .authenticating)   // nowy prompt nadal trwa
        XCTAssertEqual(s.pendingAuthAppID, id)
        XCTAssertEqual(recorder.count, 0)
        XCTAssertEqual(controller.activatedSelfCount, 0)

        auth.resolve(1, with: .success)
        let secondResult = await second.value
        XCTAssertTrue(secondResult)
        s = await service.currentState()
        XCTAssertEqual(s.apps[0].status, .unlocked)
        XCTAssertFalse(s.recentActivity.contains { $0.kind == .authFailed })
    }

    private func sampleApp(fallback: Bool = false, requireTouchID: Bool = true) -> ProtectedApp {
        ProtectedApp(bundleIdentifier: "org.whispersystems.signal-desktop", displayName: "Signal",
                     applicationURL: URL(fileURLWithPath: "/Applications/Signal.app"),
                     requireTouchID: requireTouchID, allowPasswordFallback: fallback)
    }

    func testSuccessfulAuthUnlocksAndActivates() async {
        let controller = FakeAppController()
        let auth = FakeAuthenticator(result: .success)
        let service = InProcessEnforcementService(controller: controller, authenticator: auth)
        await service.addProtectedApp(sampleApp())
        let id = await service.currentState().apps[0].id

        let ok = await service.authenticate(appID: id)
        XCTAssertTrue(ok)
        let s = await service.currentState()
        XCTAssertEqual(s.apps[0].status, .unlocked)
        XCTAssertNil(s.pendingAuthAppID)
        XCTAssertEqual(controller.activated, ["org.whispersystems.signal-desktop"])
        XCTAssertEqual(auth.calls.first?.policy, .biometricsOnly)   // brak fallbacku
    }

    func testFailedAuthStaysLocked() async {
        let controller = FakeAppController()
        let auth = FakeAuthenticator(result: .failed)
        let service = InProcessEnforcementService(controller: controller, authenticator: auth)
        await service.addProtectedApp(sampleApp())
        let id = await service.currentState().apps[0].id

        let ok = await service.authenticate(appID: id)
        XCTAssertFalse(ok)
        let s = await service.currentState()
        XCTAssertNotEqual(s.apps[0].status, .unlocked)
        XCTAssertTrue(controller.activated.isEmpty)
        XCTAssertTrue(s.recentActivity.contains { $0.kind == .authFailed })
    }

    func testFallbackPolicyPassedWhenAllowed() async {
        let auth = FakeAuthenticator(result: .success)
        let service = InProcessEnforcementService(authenticator: auth)
        await service.addProtectedApp(sampleApp(fallback: true))
        let id = await service.currentState().apps[0].id
        _ = await service.authenticate(appID: id)
        XCTAssertEqual(auth.calls.first?.policy, .biometricsOrPassword)
    }

    func testPreferPasswordForcesPasswordPolicy() async {
        let auth = FakeAuthenticator(result: .success)
        let service = InProcessEnforcementService(authenticator: auth)
        await service.addProtectedApp(sampleApp(fallback: false))   // apka biometrics-only
        let id = await service.currentState().apps[0].id
        _ = await service.authenticate(appID: id, preferPassword: true)
        // Mimo biometrics-only, „Use Password" wymusza wyłącznie hasło.
        XCTAssertEqual(auth.calls.first?.policy, .passwordOnly)
    }

    func testPasswordOnlyPolicyPassedForPasswordOnlyApp() async {
        let auth = FakeAuthenticator(result: .success)
        let service = InProcessEnforcementService(authenticator: auth)
        await service.addProtectedApp(sampleApp(fallback: true, requireTouchID: false))
        let id = await service.currentState().apps[0].id
        _ = await service.authenticate(appID: id)
        XCTAssertEqual(auth.calls.first?.policy, .passwordOnly)
    }

    func testAuthWithoutAuthenticatorFails() async {
        let service = InProcessEnforcementService()   // brak autentykatora
        await service.addProtectedApp(sampleApp())
        let id = await service.currentState().apps[0].id
        let ok = await service.authenticate(appID: id)
        XCTAssertFalse(ok)
    }

    func testFailedAuthenticationRecordsPhotoWhenOptedIn() async {
        let auth = FakeAuthenticator(result: .failed)
        let recorder = FakeFailedAttemptRecorder()
        let service = InProcessEnforcementService(
            authenticator: auth,
            failedAttemptRecorder: recorder
        )
        var config = AppConfiguration.default
        config.captureFailedAttempts = true
        await service.updateConfiguration(config)
        await service.addProtectedApp(sampleApp())
        let id = await service.currentState().apps[0].id

        _ = await service.authenticate(appID: id)

        XCTAssertEqual(recorder.count, 1)
        let event = await service.currentState().recentActivity.first { $0.kind == .authFailed }
        XCTAssertEqual(event?.evidencePhotoFilename, "failed-attempt.jpg")
    }

    func testCanceledAuthenticationRecordsPhotoWhenOptedIn() async {
        let auth = FakeAuthenticator(result: .canceled)
        let recorder = FakeFailedAttemptRecorder()
        let service = InProcessEnforcementService(
            authenticator: auth,
            failedAttemptRecorder: recorder
        )
        var config = AppConfiguration.default
        config.captureFailedAttempts = true
        await service.updateConfiguration(config)
        await service.addProtectedApp(sampleApp())
        let id = await service.currentState().apps[0].id

        _ = await service.authenticate(appID: id)

        XCTAssertEqual(recorder.count, 1)
    }
}
