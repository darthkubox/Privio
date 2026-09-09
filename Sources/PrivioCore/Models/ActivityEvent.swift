import Foundation

/// Wpis lokalnej, prywatnej historii zdarzeń (sekcja 19).
///
/// Przechowujemy WYŁĄCZNIE metadane stanu (co, kiedy, dlaczego) - nigdy treści
/// chronionych aplikacji. Historia zostaje lokalnie na Macu, bez chmury.
public struct ActivityEvent: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case unlocked
        case locked
        case quit
        case protectionEnabled
        case protectionDisabled
        case authFailed
    }

    /// Powód zdarzenia - pozwala na czytelny opis „locked - inactivity".
    public enum Reason: String, Codable, Hashable, Sendable {
        case userAction
        case inactivity
        case screenLock
        case sleep
        case appLaunch
        case sessionChange
        case authentication
        case proximity
        case none
    }

    public let id: UUID
    public let date: Date
    public let kind: Kind
    public let reason: Reason
    /// Nazwa apki, której dotyczy zdarzenie (nil dla zdarzeń globalnych).
    public let appDisplayName: String?
    public let bundleIdentifier: String?
    /// Lokalna nazwa zdjęcia dowodowego. Bez ścieżki i bez danych wysyłanych poza Maca.
    public let evidencePhotoFilename: String?

    public init(
        id: UUID = UUID(),
        date: Date,
        kind: Kind,
        reason: Reason = .none,
        appDisplayName: String? = nil,
        bundleIdentifier: String? = nil,
        evidencePhotoFilename: String? = nil
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.reason = reason
        self.appDisplayName = appDisplayName
        self.bundleIdentifier = bundleIdentifier
        self.evidencePhotoFilename = evidencePhotoFilename
    }

    /// Czytelny opis zdarzenia, np. „Signal locked - inactivity".
    public var summary: String {
        let subject = appDisplayName ?? "Privio"
        let verb: String
        switch kind {
        case .unlocked:           verb = "unlocked"
        case .locked:             verb = "locked"
        case .quit:               verb = "quit"
        case .protectionEnabled:  verb = "protection enabled"
        case .protectionDisabled: verb = "protection disabled"
        case .authFailed:         verb = "authentication failed"
        }
        if reason == .none || reason == .userAction {
            return "\(subject) \(verb)"
        }
        return "\(subject) \(verb) - \(reason.humanReadable)"
    }

    public var symbolName: String {
        switch kind {
        case .unlocked:           return "lock.open.fill"
        case .locked:             return "lock.fill"
        case .quit:               return "xmark.circle.fill"
        case .protectionEnabled:  return "checkmark.shield.fill"
        case .protectionDisabled: return "shield.slash.fill"
        case .authFailed:         return "exclamationmark.triangle.fill"
        }
    }
}

extension ActivityEvent.Reason {
    var humanReadable: String {
        switch self {
        case .userAction:    return "manual"
        case .inactivity:    return "inactivity"
        case .screenLock:    return "screen locked"
        case .sleep:         return "sleep"
        case .appLaunch:     return "app launched"
        case .sessionChange: return "session changed"
        case .authentication:return "authentication"
        case .proximity:     return "moved away"
        case .none:          return ""
        }
    }
}
