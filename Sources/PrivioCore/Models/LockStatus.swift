import Foundation

/// Ulotny stan blokady pojedynczej chronionej aplikacji.
///
/// Świadomie NIE jest częścią `ProtectedApp` (persist) - zgodnie z sekcją 7
/// oddzielamy konfigurację od stanu bezpieczeństwa. Po restarcie procesu
/// wszystko wraca do `.locked` (żadnego trwałego „unlocked = true").
public enum LockStatus: String, Codable, Hashable, Sendable {
    /// Ochrona wyłączona dla tej apki - Privio jej nie pilnuje.
    case unprotected
    /// Chroniona i zablokowana - wymaga uwierzytelnienia.
    case locked
    /// Trwa uwierzytelnianie (pokazane okno auth / systemowy prompt).
    case authenticating
    /// Odblokowana dzięki ważnemu, krótkotrwałemu tokenowi autoryzacji.
    case unlocked

    /// Etykieta niezależna od koloru (sekcja 23: nie komunikuj stanu samym kolorem).
    public var label: String {
        switch self {
        case .unprotected:    return "Off"
        case .locked:         return "Locked"
        case .authenticating: return "Authenticating…"
        case .unlocked:       return "Unlocked"
        }
    }

    /// Nazwa symbolu SF do wizualnego (nie tylko kolorystycznego) rozróżnienia.
    public var symbolName: String {
        switch self {
        case .unprotected:    return "lock.open.trianglebadge.exclamationmark"
        case .locked:         return "lock.fill"
        case .authenticating: return "lock.rotation"
        case .unlocked:       return "lock.open.fill"
        }
    }
}
