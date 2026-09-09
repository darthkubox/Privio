import Foundation

/// Polityka uwierzytelnienia dla apki (sekcja 11).
public enum AuthPolicy: Sendable, Equatable {
    /// Wyłącznie biometria (Touch ID). Bez fallbacku do hasła.
    case biometricsOnly
    /// Biometria lub hasło Maca.
    case biometricsOrPassword
    /// Wyłącznie hasło konta Maca, bez Touch ID.
    case passwordOnly
}

/// Wynik próby uwierzytelnienia.
public enum AuthResult: Sendable, Equatable {
    case success
    case failed
    case canceled
    case unavailable(String)
}

/// Krótkotrwała autoryzacja wydana po udanym uwierzytelnieniu (sekcja 12).
/// Związana z konkretną apką i sesją; NIE globalny „unlocked = true".
public struct AuthorizationToken: Sendable, Equatable {
    public let bundleIdentifier: String
    public let issuedAt: Date
    public let expiresAt: Date
    /// Podpis wyzwania kluczem z Secure Enclave (dowód obecności). Może być nil,
    /// jeśli SE niedostępne - wtedy polegamy na wyniku LocalAuthentication.
    public let signature: Data?

    public init(bundleIdentifier: String, issuedAt: Date, expiresAt: Date, signature: Data?) {
        self.bundleIdentifier = bundleIdentifier
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.signature = signature
    }

    public func isValid(at date: Date) -> Bool { date < expiresAt }
}

/// Abstrakcja uwierzytelnienia biometrycznego. Produkcyjnie: LocalAuthentication
/// + Secure Enclave. W testach: atrapa. Pozwala też przenieść realizację do
/// agenta bez zmian w logice enforcement.
public protocol BiometricAuthenticating: Sendable {
    /// Uruchamia natywny prompt biometrii/hasła. Zwraca wynik. `appName` trafia
    /// do treści systemowego promptu („…to unlock <appName>"); `bundleID` wiąże
    /// dowód autoryzacji (podpis SE) z konkretną apką (sekcja 12).
    func authenticate(bundleID: String, appName: String, policy: AuthPolicy) async -> AuthResult
    /// Uwierzytelnienie dla akcji Privio (np. wyłączenie ochrony / zamknięcie) -
    /// dowolny, w pełni gotowy powód, bez wiązania z apką (sekcja 18).
    func authenticate(reason: String, policy: AuthPolicy) async -> AuthResult
}
