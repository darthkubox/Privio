import SwiftUI
import AppKit
import PrivioCore

/// Okno główne: sidebar + obszar treści (wg mockupu).
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(ProximityController.self) private var proximity

    private var isSnapshot: Bool {
        ProcessInfo.processInfo.environment["PRIVIO_SNAPSHOT"] != nil
    }

    var body: some View {
        Group {
            if isSnapshot || model.mainWindowAccessGranted {
                mainContent
            } else {
                panelLockedView
            }
        }
        .background(Color.privioBackground)
        .task { model.startObserving(); proximity.start() }
        // Zatwierdzenie umowy licencyjnej przy pierwszym uruchomieniu („instalacja").
        .sheet(isPresented: Binding(
            get: { !isSnapshot && model.mainWindowAccessGranted && !model.licenseAccepted },
            set: { _ in }   // zamknięcie tylko przez Accept/Decline
        )) {
            LicenseAgreementView(
                requireAcceptance: true,
                onAccept: { model.acceptLicense() },
                onDecline: { NSApp.terminate(nil) })
        }
        // Ikona w Docku tylko gdy otwarte okno ustawień: przy otwarciu → regular,
        // przy zamknięciu → accessory (Privio zostaje wyłącznie w pasku menu).
        .onAppear {
            guard !isSnapshot else { return }
            PrivioAuthDiag.log("RootView.onAppear activate + " + PrivioAuthDiag.snapshot("onAppear"))
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            // Prompt Touch ID pokazujemy dopiero, gdy Privio jest frontmost - po
            // relaunchu z aktualizacji Sparkle inaczej lądował w tle bez fokusu.
            model.unlockMainWindowWhenFrontmost()
        }
        .onDisappear {
            guard !isSnapshot else { return }
            model.lockMainWindow()
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private var mainContent: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 232)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.privioBackground)
        }
    }

    private var panelLockedView: some View {
        VStack(spacing: 16) {
            PrivioLogo().frame(width: 54, height: 68)
            Text("Privio is locked")
                .font(.privioSystem(size: 24, weight: .semibold))
                .foregroundStyle(Color.privioTextPrimary)
            Text("Confirm with Touch ID or your Mac password to open the control panel.")
                .font(.privioSystem(size: 13.5))
                .foregroundStyle(Color.privioTextSecondary)
                .multilineTextAlignment(.center)
            Button("Unlock Privio") {
                Task { _ = await model.unlockMainWindow() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.privioPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    @ViewBuilder
    private var content: some View {
        switch model.selectedSection {
        case .protectedApps: ProtectedAppsView()
        case .websites:      ProtectedWebsitesView()
        case .privacyCurtain: PrivacyCurtainView()
        case .vault:         VaultView()
        case .proximity:     ProximityView()
        case .activity:      ActivityView()
        case .schedules:     SchedulesView()
        case .settings:      SettingsView()
        case .about:         AboutView()
        }
    }
}

#if DEBUG
#Preview {
    let seed = PreviewData.sampleState
    let service = InProcessEnforcementService(initialState: seed)
    RootView()
        .environment(AppModel(service: service, initialState: seed))
        .environment(VaultController(isSnapshot: true))
        .environment(ProximityController(isSnapshot: true))
        .frame(width: 960, height: 640)
}
#endif
