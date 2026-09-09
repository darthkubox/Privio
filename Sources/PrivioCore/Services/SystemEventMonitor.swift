import Foundation
import AppKit

/// Zdarzenia systemowe istotne dla blokady (sekcja 13).
public enum SystemEvent: Sendable, Equatable {
    case screenLocked
    case screenUnlocked
    case willSleep
    case didWake
    case sessionResigned      // Fast User Switching - nasza sesja przestaje być aktywna
    case sessionBecameActive
}

/// Źródło zdarzeń systemowych. Abstrakcja pod testy i przyszły agent.
public protocol SystemEventMonitoring: Sendable {
    func start() -> AsyncStream<SystemEvent>
    func stop()
}

/// Implementacja oparta o `DistributedNotificationCenter` (screen lock) oraz
/// `NSWorkspace` (sleep/wake, przełączanie sesji). Event‑driven, bez pollingu.
public final class WorkspaceSystemEventMonitor: SystemEventMonitoring, @unchecked Sendable {
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var distributedObservers: [(DistributedNotificationCenter, NSObjectProtocol)] = []

    public init() {}

    public func start() -> AsyncStream<SystemEvent> {
        AsyncStream { continuation in
            let ws = NSWorkspace.shared.notificationCenter
            func observe(_ center: NotificationCenter, _ name: Notification.Name, _ event: SystemEvent) {
                let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                    continuation.yield(event)
                }
                observers.append((center, token))
            }
            observe(ws, NSWorkspace.willSleepNotification, .willSleep)
            observe(ws, NSWorkspace.didWakeNotification, .didWake)
            observe(ws, NSWorkspace.sessionDidResignActiveNotification, .sessionResigned)
            observe(ws, NSWorkspace.sessionDidBecomeActiveNotification, .sessionBecameActive)

            // Blokada ekranu - nazwy „nieoficjalne", ale publiczne i powszechnie używane.
            let dnc = DistributedNotificationCenter.default()
            func observeDistributed(_ name: String, _ event: SystemEvent) {
                let token = dnc.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { _ in
                    continuation.yield(event)
                }
                distributedObservers.append((dnc, token))
            }
            observeDistributed("com.apple.screenIsLocked", .screenLocked)
            observeDistributed("com.apple.screenIsUnlocked", .screenUnlocked)

            continuation.onTermination = { [weak self] _ in self?.stop() }
        }
    }

    public func stop() {
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        distributedObservers.forEach { $0.0.removeObserver($0.1) }
        distributedObservers.removeAll()
    }
}
