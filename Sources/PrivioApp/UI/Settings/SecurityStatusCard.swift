import SwiftUI
import PrivioCore

/// Uczciwy status ochrony (sekcje 23-24): nigdy nie twierdzimy „Protected", gdy
/// egzekwowanie nie działa. Stan pokazywany kropką + ikoną + tekstem (nie samym
/// kolorem - dostępność).
struct SecurityStatusCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SettingsCard("Protection status") {
            if model.state.protectionActive {
                line(color: .privioUnlocked, symbol: "checkmark.shield.fill",
                     text: "Protection is active", detail: "Apps enforced: \(model.protectedCount)")
            } else {
                line(color: .privioDanger, symbol: "exclamationmark.shield.fill",
                     text: "Protection is off", detail: "Protected apps are NOT being enforced")
            }
            Divider().overlay(Color.privioSeparator)
            if model.touchIDAvailable {
                line(color: .privioUnlocked, symbol: "touchid", text: "Touch ID available")
            } else {
                line(color: .privioBright, symbol: "touchid",
                     text: "Touch ID unavailable", detail: "Unlock uses your Mac password")
            }
            Divider().overlay(Color.privioSeparator)
            if model.loginItemEnabled {
                line(color: .privioUnlocked, symbol: "power", text: "Starts at login")
            } else {
                line(color: .privioTextTertiary, symbol: "power",
                     text: "Not starting at login", detail: "Protection won’t resume automatically after a restart")
            }
            if !model.state.configIntegrityValid {
                Divider().overlay(Color.privioSeparator)
                line(color: .privioDanger, symbol: "exclamationmark.triangle.fill",
                     text: "Configuration integrity check failed",
                     detail: "Settings may have been modified outside Privio")
            }
            Divider().overlay(Color.privioSeparator)
            switch RecoveryController.shared.status {
            case .watching:
                line(color: .privioUnlocked, symbol: "checkmark.shield.fill",
                     text: "Automatic recovery is ready",
                     detail: "Privio restarts after an unexpected exit; protection pauses briefly")
            case .waiting:
                line(color: .privioBright, symbol: "exclamationmark.triangle.fill",
                     text: "Waiting for automatic recovery",
                     detail: "The background service has not confirmed it is watching Privio")
            case .needsApproval:
                line(color: .privioBright, symbol: "exclamationmark.triangle.fill",
                     text: "Automatic recovery needs permission",
                     detail: "Allow Privio to run in the background in System Settings")
                Button("Open Login Items settings") { RecoveryController.shared.openSystemSettings() }
            case .unavailable:
                line(color: .privioBright, symbol: "exclamationmark.triangle.fill",
                     text: "Automatic recovery is unavailable",
                     detail: "Install Privio in Applications and allow its background service")
            }
        }
    }

    private func line(color: Color, symbol: String, text: LocalizedStringKey, detail: LocalizedStringKey? = nil) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8)
            FAIcon(symbol, size: 13)
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(text).font(.privioSystem(size: 13.5)).foregroundStyle(Color.privioTextPrimary)
                if let detail {
                    Text(detail).font(.privioSystem(size: 11.5)).foregroundStyle(Color.privioTextTertiary)
                }
            }
            Spacer()
        }
    }
}
