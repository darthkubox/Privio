import Foundation
import AppKit

/// Zdarzenie cyklu życia aplikacji z `NSWorkspace` (event‑driven, ~0% CPU idle).
public enum AppEvent: Sendable, Equatable {
    case activated(bundleID: String)
    case launched(bundleID: String)
    case terminated(bundleID: String)
}

/// Źródło zdarzeń aktywacji/uruchomienia/zamknięcia aplikacji.
/// Abstrakcja pozwala wstrzyknąć atrapę w testach oraz - w przyszłości -
/// przenieść monitoring do procesu agenta bez zmian w logice enforcement.
public protocol AppActivationMonitoring: Sendable {
    func start() -> AsyncStream<AppEvent>
    func stop()
}

/// Sterowanie działającymi aplikacjami (ukryj/aktywuj/zamknij). Abstrakcja nad
/// `NSRunningApplication` - logika enforcement testowalna z atrapą.
public protocol RunningAppController: Sendable {
    func hide(bundleID: String)
    func activate(bundleID: String)
    func terminate(bundleID: String, force: Bool)
    func isRunning(bundleID: String) -> Bool
    func frontmostBundleID() -> String?
    /// Aktywuje SAMO Privio (przejęcie fokusu) - np. po anulowaniu auth, by
    /// zablokowana apka nie odzyskała fokusu i nie odkryła się z powrotem.
    func activateSelf()
}

// MARK: - Implementacje produkcyjne (AppKit)

/// Monitor oparty o `NSWorkspace.shared.notificationCenter` (bez pollingu).
public final class WorkspaceAppMonitor: AppActivationMonitoring, @unchecked Sendable {
    private var observers: [NSObjectProtocol] = []

    public init() {}

    public func start() -> AsyncStream<AppEvent> {
        AsyncStream { continuation in
            let center = NSWorkspace.shared.notificationCenter

            func observe(_ name: Notification.Name, _ make: @escaping (String) -> AppEvent) -> NSObjectProtocol {
                center.addObserver(forName: name, object: nil, queue: .main) { note in
                    guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                          let bundleID = app.bundleIdentifier else { return }
                    continuation.yield(make(bundleID))
                }
            }

            observers = [
                observe(NSWorkspace.didActivateApplicationNotification) { .activated(bundleID: $0) },
                observe(NSWorkspace.didLaunchApplicationNotification) { .launched(bundleID: $0) },
                observe(NSWorkspace.didTerminateApplicationNotification) { .terminated(bundleID: $0) },
            ]

            continuation.onTermination = { [weak self] _ in self?.stop() }
        }
    }

    public func stop() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
    }
}

/// Sterowanie aplikacjami przez `NSRunningApplication`. Akcje modyfikujące stan
/// UI wykonujemy na głównym wątku (wymóg AppKit); zapytania są bezpieczne z tła.
public struct WorkspaceAppController: RunningAppController {
    public init() {}

    private func apps(_ bundleID: String) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    }

    public func hide(bundleID: String) {
        onMain {
            let instances = self.apps(bundleID)
            // `NSRunningApplication.hide()` zwraca false, gdy systemowo nie da się ukryć
            // okna - klasycznie dla apek w trybie pełnoekranowym (własny Space). Wtedy
            // treść pozostaje widoczna; zakrywa ją zasłona blokady (`LockCoverController`).
            // Logujemy to jako sygnał diagnostyczny, ale NIE blokujemy dalszego przepływu
            // (prompt Touch ID i tak musi się pojawić).
            let results = instances.map { $0.hide() }   // wywołaj na WSZYSTKICH instancjach
            if !results.isEmpty && results.contains(false) {
                PrivioLog.enforcement.notice(
                    "hide() nie ukryło apki (np. pełny ekran) - zasłona blokady zakryje okno: \(bundleID, privacy: .public)")
            }
        }
    }

    public func activate(bundleID: String) {
        onMain {
            for app in self.apps(bundleID) {
                app.unhide()
                app.activate()
            }
        }
    }

    public func terminate(bundleID: String, force: Bool) {
        onMain {
            self.apps(bundleID).forEach { _ = force ? $0.forceTerminate() : $0.terminate() }
        }
    }

    public func isRunning(bundleID: String) -> Bool { !apps(bundleID).isEmpty }

    public func frontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    public func activateSelf() {
        Task { @MainActor in
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private func onMain(_ work: @escaping @Sendable () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            // Operacje bezpieczeństwa muszą zakończyć się przed kolejną zmianą stanu.
            // Gdy hide() było tylko async, pendingAuth trafiał do UI wcześniej i prompt
            // Touch ID pojawiał się nad wciąż czytelnym oknem chronionej aplikacji.
            DispatchQueue.main.sync(execute: work)
        }
    }
}
