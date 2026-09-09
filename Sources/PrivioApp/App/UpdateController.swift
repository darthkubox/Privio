import AppKit
import Sparkle

/// Sparkle owns download verification, update UI and authorized package install.
/// The feed and EdDSA public key are supplied through Info.plist.
@MainActor
final class UpdateController: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: self
    )

    func checkForUpdates() {
        dismissAttachedSheets()
        controller.checkForUpdates(nil)
    }

    /// Sparkle pokazuje własne okna modalne. Arkusz SwiftUI przypięty do głównego
    /// okna może stanąć nad nimi, a przy instalacji utrudnić zakończenie aplikacji.
    /// Oficjalny delegate Sparkle wywołuje tę metodę dokładnie przed prezentacją
    /// alertu modalnego, więc zamykamy wyłącznie istniejące arkusze Privio.
    func standardUserDriverWillShowModalAlert() {
        dismissAttachedSheets()
    }

    private func dismissAttachedSheets() {
        for window in NSApp.windows {
            guard let sheet = window.attachedSheet else { continue }
            window.endSheet(sheet, returnCode: .cancel)
            sheet.orderOut(nil)
        }
    }
}
