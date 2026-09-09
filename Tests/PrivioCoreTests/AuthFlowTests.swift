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

final class AuthFlowTests: XCTestCase {

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
