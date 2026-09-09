import Foundation

/// Abstrakcja zegara - pozwala wstrzykiwać deterministyczny czas w testach
/// (obliczenia bezczynności, wygasanie autoryzacji), zamiast polegać na `Date()`.
public protocol PrivioClock: Sendable {
    func now() -> Date
}

/// Produkcyjny zegar oparty o systemowy czas.
public struct SystemClock: PrivioClock {
    public init() {}
    public func now() -> Date { Date() }
}

#if DEBUG
/// Sterowalny zegar do testów jednostkowych.
public final class TestClock: PrivioClock, @unchecked Sendable {
    private var current: Date
    private let lock = NSLock()

    public init(_ start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.current = start
    }

    public func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    /// Przesuwa czas o zadaną liczbę sekund.
    public func advance(by seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        current = current.addingTimeInterval(seconds)
    }
}
#endif
