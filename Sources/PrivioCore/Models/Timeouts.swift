import Foundation

/// Presety blokady po bezczynności (sekcja 9 specyfikacji).
/// Wartość utrwalana w modelu to `TimeInterval?` (nil = nigdy); ten enum służy
/// jako wygodna lista wyboru w UI oraz do mapowania sekund ↔ etykieta.
public enum LockTimeoutPreset: CaseIterable, Identifiable, Hashable, Sendable {
    case immediately
    case after30s
    case after1m
    case after2m
    case after5m
    case after15m
    case after30m
    case never

    public var id: Self { self }

    /// nil = nigdy nie blokuj; 0 = zablokuj natychmiast po opuszczeniu apki.
    public var seconds: TimeInterval? {
        switch self {
        case .immediately: return 0
        case .after30s:    return 30
        case .after1m:     return 60
        case .after2m:     return 120
        case .after5m:     return 300
        case .after15m:    return 900
        case .after30m:    return 1800
        case .never:       return nil
        }
    }

    public var title: String {
        switch self {
        case .immediately: return "Immediately"
        case .after30s:    return "After 30 seconds"
        case .after1m:     return "After 1 minute"
        case .after2m:     return "After 2 minutes"
        case .after5m:     return "After 5 minutes"
        case .after15m:    return "After 15 minutes"
        case .after30m:    return "After 30 minutes"
        case .never:       return "Never"
        }
    }

    /// Zwarta etykieta do wyświetlenia w wierszu listy / detalu.
    public var shortTitle: String {
        switch self {
        case .immediately: return "Immediately"
        case .after30s:    return "30 seconds"
        case .after1m:     return "1 minute"
        case .after2m:     return "2 minutes"
        case .after5m:     return "5 minutes"
        case .after15m:    return "15 minutes"
        case .after30m:    return "30 minutes"
        case .never:       return "Never"
        }
    }

    /// Dopasowuje utrwaloną wartość sekund do najbliższego presetu (do UI).
    public static func from(seconds: TimeInterval?) -> LockTimeoutPreset {
        guard let seconds else { return .never }
        return allCases
            .filter { $0.seconds != nil }
            .min(by: { abs(($0.seconds ?? 0) - seconds) < abs(($1.seconds ?? 0) - seconds) })
            ?? .never
    }
}

/// Presety automatycznego zamknięcia po bezczynności (sekcja 9 i 10).
public enum QuitTimeoutPreset: CaseIterable, Identifiable, Hashable, Sendable {
    case never
    case after1m
    case after5m
    case after15m
    case after30m
    case after1h

    public var id: Self { self }

    public var seconds: TimeInterval? {
        switch self {
        case .never:    return nil
        case .after1m:  return 60
        case .after5m:  return 300
        case .after15m: return 900
        case .after30m: return 1800
        case .after1h:  return 3600
        }
    }

    public var title: String {
        switch self {
        case .never:    return "Never"
        case .after1m:  return "After 1 minute"
        case .after5m:  return "After 5 minutes"
        case .after15m: return "After 15 minutes"
        case .after30m: return "After 30 minutes"
        case .after1h:  return "After 1 hour"
        }
    }

    public var shortTitle: String {
        switch self {
        case .never:    return "Never"
        case .after1m:  return "1 minute"
        case .after5m:  return "5 minutes"
        case .after15m: return "15 minutes"
        case .after30m: return "30 minutes"
        case .after1h:  return "1 hour"
        }
    }

    public static func from(seconds: TimeInterval?) -> QuitTimeoutPreset {
        guard let seconds else { return .never }
        return allCases
            .filter { $0.seconds != nil }
            .min(by: { abs(($0.seconds ?? 0) - seconds) < abs(($1.seconds ?? 0) - seconds) })
            ?? .never
    }
}

/// Walidacja logiczna zależności lock ↔ quit (sekcja 9: ostrzeż, jeśli apka
/// zostanie zamknięta zanim zdąży się zablokować).
public enum TimeoutValidation {
    /// Zwraca ostrzeżenie, jeśli quit nastąpi przed lock (quit < lock).
    public static func warning(lock: TimeInterval?, quit: TimeInterval?) -> String? {
        guard let quit else { return nil }          // quit = never → brak konfliktu
        guard let lock else {
            // lock = never, ale quit ustawiony → apka zostanie zamknięta bez blokady.
            return "This app will quit on inactivity but never lock first."
        }
        if quit <= lock {
            return "Quit timeout is shorter than the lock timeout - the app will quit before it locks."
        }
        return nil
    }
}
