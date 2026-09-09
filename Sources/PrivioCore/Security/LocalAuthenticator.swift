import Foundation
import LocalAuthentication
import Security

/// Produkcyjny autentykator: natywny prompt `LocalAuthentication` (prawdziwy
/// Touch ID / hasło Maca) + dowód obecności podpisany kluczem Secure Enclave.
///
/// WAŻNE (sekcja 11/17): to jedyne źródło biometrii - Privio nigdy nie tworzy
/// własnego dialogu biometrii ani nie dotyka danych odcisku palca.
public struct LocalAuthenticator: BiometricAuthenticating {
    private let clock: PrivioClock
    /// TTL wydawanej autoryzacji (dowód SE). Krótkotrwałe (sekcja 12).
    private let tokenTTL: TimeInterval

    public init(clock: PrivioClock = SystemClock(), tokenTTL: TimeInterval = 300) {
        self.clock = clock
        self.tokenTTL = tokenTTL
    }

    public func authenticate(bundleID: String, appName: String, policy: AuthPolicy) async -> AuthResult {
        let context = LAContext()
        let outcome = await evaluate(context: context, policy: policy,
                                     reason: Self.localizedReason(appName: appName))
        guard outcome == .success else { return outcome }

        // Dowód obecności: podpisz wyzwanie związane z apką (best‑effort). Reużywa
        // uwierzytelnionego kontekstu, więc bez drugiego promptu.
        let nonce = randomNonce()
        var challenge = Data(bundleID.utf8)
        challenge.append(nonce)
        let signature = SecureEnclaveKey.sign(challenge, context: context)
        let now = clock.now()
        let token = AuthorizationToken(bundleIdentifier: bundleID, issuedAt: now,
                                       expiresAt: now.addingTimeInterval(tokenTTL),
                                       signature: signature)
        PrivioLog.auth.info("Autoryzacja \(token.signature != nil ? "SE" : "LA") dla \(bundleID, privacy: .public)")
        return .success
    }

    public func authenticate(reason: String, policy: AuthPolicy) async -> AuthResult {
        await evaluate(context: LAContext(), policy: policy, reason: reason)
    }

    /// Wspólna ewaluacja LocalAuthentication (bez SE) używana przez oba warianty.
    private func evaluate(context: LAContext, policy: AuthPolicy, reason: String) async -> AuthResult {
        if policy == .passwordOnly {
            return await evaluatePasswordOnly(context: context, reason: reason)
        }

        let laPolicy: LAPolicy = policy == .biometricsOnly
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication
        if policy == .biometricsOnly {
            context.localizedFallbackTitle = ""   // ukryj przycisk hasła
        }
        var availabilityError: NSError?
        guard context.canEvaluatePolicy(laPolicy, error: &availabilityError) else {
            return .unavailable(availabilityError?.localizedDescription ?? "Biometrics unavailable")
        }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(laPolicy, localizedReason: reason) { success, error in
                if success {
                    continuation.resume(returning: .success)
                } else if let laError = error as? LAError,
                          [.userCancel, .systemCancel, .appCancel].contains(laError.code) {
                    continuation.resume(returning: .canceled)
                } else {
                    continuation.resume(returning: .failed)
                }
            }
        }
    }

    /// `LAPolicy.deviceOwnerAuthentication` dopuszcza biometrię, więc nie jest
    /// trybem „Password only”. Dostęp kontrolowany flagą `.devicePasscode`
    /// wymusza uwierzytelnienie hasłem urządzenia/konta bez Touch ID.
    private func evaluatePasswordOnly(context: LAContext, reason: String) async -> AuthResult {
        var accessError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .devicePasscode,
            &accessError
        ) else {
            let message = accessError?.takeRetainedValue().localizedDescription
                ?? "Mac password authentication unavailable"
            return .unavailable(message)
        }

        return await withCheckedContinuation { continuation in
            context.evaluateAccessControl(accessControl, operation: .useItem, localizedReason: reason) {
                success, error in
                if success {
                    continuation.resume(returning: .success)
                } else if let laError = error as? LAError,
                          [.userCancel, .systemCancel, .appCancel].contains(laError.code) {
                    continuation.resume(returning: .canceled)
                } else {
                    continuation.resume(returning: .failed)
                }
            }
        }
    }

    /// Powód dopasowany do języka systemu - macOS lokalizuje ramkę promptu, ale
    /// nie nasz tekst, więc dobieramy go sami (np. PL: „…próbuje odblokować Chess").
    static func localizedReason(appName: String) -> String {
        let language = Locale.preferredLanguages.first ?? "en"
        if language.hasPrefix("pl") { return "odblokować \(appName)" }
        return "unlock \(appName)"
    }

    private func randomNonce(_ length: Int = 32) -> Data {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return Data(bytes)
    }
}
