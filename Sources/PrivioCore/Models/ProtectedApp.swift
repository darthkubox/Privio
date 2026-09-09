import Foundation

/// Utrwalana konfiguracja chronionej aplikacji (sekcja 7 specyfikacji).
///
/// Tożsamością główną jest `bundleIdentifier` - NIE ścieżka na dysku (sekcja 5),
/// dzięki czemu aktualizacja/przeniesienie apki nie gubi ochrony. `applicationURL`
/// trzymamy pomocniczo (ikona, ostatnia znana lokalizacja), ale odświeżamy ją
/// po bundleID.
///
/// To jest WYŁĄCZNIE konfiguracja. Stan ulotny (isLocked, znaczniki czasu,
/// tokeny autoryzacji) żyje osobno w warstwie enforcement (sekcja 7).
public struct ProtectedApp: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID

    /// Tożsamość główna. Po niej rozpoznajemy aktywację apki.
    public var bundleIdentifier: String
    public var displayName: String
    /// Ostatnia znana lokalizacja pakietu .app (do ikony i podpowiedzi).
    public var applicationURL: URL

    public var protectionEnabled: Bool

    /// nil = nigdy nie blokuj po bezczynności; 0 = natychmiast po opuszczeniu.
    public var lockAfterInactivity: TimeInterval?
    /// nil = nigdy nie zamykaj po bezczynności.
    public var quitAfterInactivity: TimeInterval?

    public var lockAfterScreenLock: Bool
    public var lockAfterSleep: Bool

    public var requireTouchID: Bool
    public var allowPasswordFallback: Bool

    /// Jeśli apka nie zamknie się łagodnie po auto‑quit - wymuś zamknięcie (force).
    /// Domyślnie OFF (możliwa utrata niezapisanych danych - sekcja 10).
    public var forceQuitIfUnresponsive: Bool

    public init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        displayName: String,
        applicationURL: URL,
        protectionEnabled: Bool = true,
        lockAfterInactivity: TimeInterval? = 120,
        quitAfterInactivity: TimeInterval? = nil,
        lockAfterScreenLock: Bool = true,
        lockAfterSleep: Bool = true,
        requireTouchID: Bool = true,
        allowPasswordFallback: Bool = true,
        forceQuitIfUnresponsive: Bool = false
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.applicationURL = applicationURL
        self.protectionEnabled = protectionEnabled
        self.lockAfterInactivity = lockAfterInactivity
        self.quitAfterInactivity = quitAfterInactivity
        self.lockAfterScreenLock = lockAfterScreenLock
        self.lockAfterSleep = lockAfterSleep
        self.requireTouchID = requireTouchID
        self.allowPasswordFallback = allowPasswordFallback
        self.forceQuitIfUnresponsive = forceQuitIfUnresponsive
    }

    public var lockPreset: LockTimeoutPreset {
        LockTimeoutPreset.from(seconds: lockAfterInactivity)
    }

    public var quitPreset: QuitTimeoutPreset {
        QuitTimeoutPreset.from(seconds: quitAfterInactivity)
    }

    /// Ostrzeżenie o niespójnej konfiguracji lock/quit (sekcja 9).
    public var timeoutWarning: String? {
        TimeoutValidation.warning(lock: lockAfterInactivity, quit: quitAfterInactivity)
    }
}
