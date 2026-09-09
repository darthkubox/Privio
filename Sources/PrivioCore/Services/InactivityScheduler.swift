import Foundation

/// Planowanie akcji po czasie bezczynności (sekcja 8). Abstrakcja pozwala na
/// deterministyczne testy (atrapa odpalana ręcznie) oraz utrzymuje logikę
/// event‑driven - bez pętli pollingu (sekcja 24).
public protocol InactivityScheduling: Sendable {
    /// Zaplanuj `action` po `seconds` dla klucza `key`. Ponowne wywołanie z tym
    /// samym `key` anuluje poprzednie zaplanowanie (reset przy powrocie do apki).
    func schedule(key: String, seconds: TimeInterval, action: @escaping @Sendable () -> Void)
    func cancel(key: String)
    func cancelAll()
}

/// Produkcyjny scheduler oparty o `Task.sleep` - jeden lekki task na klucz,
/// zero CPU w oczekiwaniu. Odpala się raz, po czym się usuwa.
public final class RealInactivityScheduler: InactivityScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [String: Task<Void, Never>] = [:]

    public init() {}

    public func schedule(key: String, seconds: TimeInterval, action: @escaping @Sendable () -> Void) {
        cancel(key: key)
        let clamped = max(0, seconds)
        let task = Task { [weak self] in
            if clamped > 0 {
                try? await Task.sleep(nanoseconds: UInt64(clamped * 1_000_000_000))
            }
            if Task.isCancelled { return }
            action()
            self?.remove(key)
        }
        lock.lock(); tasks[key] = task; lock.unlock()
    }

    public func cancel(key: String) {
        lock.lock(); let task = tasks.removeValue(forKey: key); lock.unlock()
        task?.cancel()
    }

    public func cancelAll() {
        lock.lock(); let all = tasks; tasks.removeAll(); lock.unlock()
        all.values.forEach { $0.cancel() }
    }

    private func remove(_ key: String) {
        lock.lock(); tasks[key] = nil; lock.unlock()
    }
}
