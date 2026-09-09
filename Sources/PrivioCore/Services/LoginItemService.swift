import Foundation
import ServiceManagement

/// Autostart przy logowaniu (sekcja 4/20) przez `SMAppService` - nowoczesny,
/// wspierany mechanizm (bez legacy launchd plistów). Rejestruje samą aplikację
/// jako element logowania; użytkownik zatwierdza w Ustawieniach › Elementy logowania.
///
/// Uwaga: pełna niezawodność wymaga stabilnej lokalizacji i podpisu (Developer ID).
/// Przy podpisie ad‑hoc / buildzie z DerivedData rejestracja bywa mniej pewna -
/// błędy raportujemy, nie udając sukcesu.
public struct LoginItemService: Sendable {
    public init() {}

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private var isCanonicalInstalledApp: Bool {
        Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL.path == "/Applications/Privio.app"
    }

    /// Zwraca faktyczny stan po próbie (może różnić się od żądanego, jeśli system
    /// wymaga zatwierdzenia lub rejestracja się nie powiodła).
    @discardableResult
    public func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                guard isCanonicalInstalledApp else {
                    PrivioLog.persistence.error("Refusing to register a non-/Applications Privio build as a login item")
                    return false
                }
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            PrivioLog.persistence.error("SMAppService \(enabled ? "register" : "unregister") nieudane: \(error.localizedDescription, privacy: .public)")
        }
        return isEnabled
    }

    /// Rebind an existing login-item record to the canonical installed bundle.
    /// This repairs registrations accidentally created while a DerivedData build
    /// was running, without ever registering that development copy again.
    @discardableResult
    public func refreshInstalledRegistration() -> Bool {
        guard isCanonicalInstalledApp, isEnabled else { return isEnabled }
        do {
            try SMAppService.mainApp.unregister()
            try SMAppService.mainApp.register()
        } catch {
            PrivioLog.persistence.error("SMAppService registration refresh failed: \(error.localizedDescription, privacy: .public)")
        }
        return isEnabled
    }
}
