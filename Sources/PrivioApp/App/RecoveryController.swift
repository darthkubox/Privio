import AppKit
import Observation
import PrivioCore
import ServiceManagement

@MainActor @Observable
final class RecoveryController {
    static let shared = RecoveryController()
    enum Status { case unavailable, waiting, needsApproval, watching }
    private(set) var status: Status = .unavailable
    private let service = SMAppService.agent(plistName: "com.privio.Privio.Watchdog.plist")
    private let store = RecoveryStore()
    private var timer: Timer?
    private var uninstalled = false

    private var session: RecoverySession? {
        NSRunningApplication.current.launchDate.map {
            RecoverySession(pid: ProcessInfo.processInfo.processIdentifier, launchedAt: $0)
        }
    }

    private var isInstalled: Bool {
        Bundle.main.bundleURL.resolvingSymlinksInPath().path == "/Applications/Privio.app"
    }

    func start() {
        guard isInstalled, ProcessInfo.processInfo.environment["PRIVIO_SNAPSHOT"] == nil,
              ProcessInfo.processInfo.environment["PRIVIO_VAULT_ICON_SNAPSHOT"] == nil else { return }
        do {
            // On a first-ever installation macOS can report .notFound for a
            // valid bundled service until register() introduces it to BTM.
            // https://developer.apple.com/forums/thread/719862
            let registrationStatus = service.status
            if registrationStatus == .notRegistered || registrationStatus == .notFound { try service.register() }
        } catch {
            PrivioLog.monitor.error("Recovery registration failed: \(error.localizedDescription, privacy: .public)")
        }
        refreshStatus()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
    }

    private func refreshStatus() {
        switch service.status {
        case .enabled:
            status = session.map { store.isWatching($0) } == true ? .watching : .waiting
        case .requiresApproval: status = .needsApproval
        default: status = .unavailable
        }
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }

    /// Called only after the vault has safely unmounted. Force Quit/SIGKILL never
    /// reaches this point, so it cannot leave behind a graceful-exit permit.
    func prepareForTermination() -> Bool {
        guard isInstalled, !uninstalled else { return true }
        guard let session else { return false }
        do {
            try store.permitExit(session)
            return true
        } catch {
            PrivioLog.monitor.error("Cannot permit graceful exit: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Privio could not finish quitting", comment: "Recovery error")
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return false
        }
    }

    func uninstall() -> Bool {
        guard isInstalled else { return true }
        do {
            let registrationStatus = service.status
            if registrationStatus == .enabled || registrationStatus == .requiresApproval { try service.unregister() }
            uninstalled = true
            timer?.invalidate()
            status = .unavailable
            return true
        } catch {
            PrivioLog.monitor.error("Recovery unregister failed: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Privio could not remove its background service", comment: "Recovery error")
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return false
        }
    }
}
