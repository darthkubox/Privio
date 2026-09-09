import SwiftUI
import AppKit
import PrivioCore

/// Zawartość rozwijanego panelu w pasku menu (sekcja 18, mockup).
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(VaultController.self) private var vault
    @Environment(ProximityController.self) private var proximity
    @Environment(\.openWindow) private var openWindow
    @State private var showAllApps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Nagłówek
            HStack {
                HStack(spacing: 8) {
                    PrivioSmallLogo().frame(width: 14, height: 20)
                    Text("Privio").font(.privioSystem(size: 14, weight: .semibold))
                        .foregroundStyle(Color.privioTextPrimary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Text(NSLocalizedString(model.state.protectionActive ? "Active" : "Off",
                                           comment: "Global protection status"))
                        .font(.privioSystem(size: 12, weight: .medium))
                        .foregroundStyle(model.state.protectionActive ? Color.privioUnlocked : Color.privioDanger)
                    // Włącz/wyłącz ochronę bezpośrednio z panelu (wyłączenie → auth).
                    Toggle("", isOn: Binding(
                        get: { model.state.protectionActive },
                        set: { model.setProtectionActive($0) }
                    ))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small).tint(.privioPrimary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            // Zasłona prywatności (Privacy Curtain) - osobny moduł, dodatkowa pozycja.
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    FAIcon("eye.slash.fill", size: 12)
                        .frame(width: 16)
                        .foregroundStyle(Color.privioTextSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Privacy Curtain")
                            .font(.privioSystem(size: 13, weight: .medium))
                            .foregroundStyle(Color.privioTextPrimary)
                        Text(String(format: NSLocalizedString("Reveal: hold %@", comment: "Reveal shortcut in menu bar"),
                                    ShortcutRecorderField.display(model.state.configuration.privacyRevealHoldShortcut)))
                            .font(.privioSystem(size: 10.5))
                            .foregroundStyle(Color.privioTextTertiary)
                    }
                    Spacer()
                    Text(NSLocalizedString(model.privacyModeEnabled ? "ON" : "OFF",
                                           comment: "Privacy curtain status"))
                        .font(.privioSystem(size: 10.5, weight: .semibold))
                        .foregroundStyle(model.privacyModeEnabled ? Color.privioUnlocked : Color.privioTextTertiary)
                    Toggle("", isOn: Binding(
                        get: { model.privacyModeEnabled },
                        set: { model.setPrivacyModeEnabled($0) }
                    ))
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(.privioPrimary)
                }
                // Szybki przełącznik stylu - tylko gdy zasłona jest włączona.
                if model.privacyModeEnabled {
                    Picker("", selection: Binding(
                        get: { model.privacyCurtainMode },
                        set: { model.setPrivacyCurtainMode($0) }
                    )) {
                        Text("Spotlight").tag(PrivacyCurtainMode.spotlight)
                        Text("Filter").tag(PrivacyCurtainMode.tint)
                        Text("Blur").tag(PrivacyCurtainMode.blur)
                    }
                    .labelsHidden().pickerStyle(.segmented).controlSize(.small)

                    Picker("", selection: Binding(
                        get: { model.privacyCurtainScope },
                        set: { model.setPrivacyCurtainScope($0) }
                    )) {
                        Text("Protected apps").tag(PrivacyCurtainScope.protectedApps)
                        Text("Whole screen").tag(PrivacyCurtainScope.fullScreen)
                    }
                    .labelsHidden().pickerStyle(.segmented).controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Divider()

            // Szyfrowany sejf - szybkie wejście bez otwierania panelu ustawień.
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    VaultStatusSymbol(state: vault.isUnlocked ? .unlocked : vault.isConfigured ? .locked : .neutral)
                        .frame(width: 15, height: 15)
                        .frame(width: 16)
                        .foregroundStyle(vault.isUnlocked ? Color.privioUnlocked : Color.privioTextSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Private Vault")
                            .font(.privioSystem(size: 13, weight: .medium))
                            .foregroundStyle(Color.privioTextPrimary)
                        Text(vault.isUnlocked ? "Mounted and readable" : vault.isConfigured ? "Encrypted and locked" : "Not configured")
                            .font(.privioSystem(size: 10.5))
                            .foregroundStyle(Color.privioTextTertiary)
                    }
                    Spacer()
                    Circle()
                        .fill(vault.isUnlocked ? Color.privioUnlocked : Color.privioTextTertiary.opacity(0.6))
                        .frame(width: 7, height: 7)
                }

                HStack(spacing: 8) {
                    Button {
                        if vault.isConfigured {
                            Task { _ = await vault.unlock(openInFinder: true) }
                        } else {
                            model.selectedSection = .vault
                            authenticateAndOpenMainWindow()
                        }
                    } label: {
                        Label {
                            Text(vault.isUnlocked ? "Open in Finder" : vault.isConfigured ? "Unlock" : "Set Up")
                        } icon: {
                            FAIcon(vault.isUnlocked ? "folder" : "touchid")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.privioPrimary).controlSize(.small)

                    if vault.isUnlocked {
                        Button("Lock") { Task { _ = await vault.lock() } }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Divider()

            // Blokada po odejściu - ten sam wyłącznik `enabled` co w oknie (spójny stan).
            // Pokazujemy, gdy jest sparowane urządzenie, żeby dało się też włączyć z powrotem.
            if model.isPro, !model.proximityConfig.trustedDeviceIDs.isEmpty {
                proximityRow
                Divider()
            }

            // Otwarte apki + ich status blokady (na żywo - tylko uruchomione).
            OpenAppsSection(showAll: $showAllApps)

            Divider()

            // Akcje
            MenuRow(title: "Lock All Apps", symbol: "lock.fill") {
                model.lockAll()
            }
            MenuRow(title: "Open Privio…", symbol: "macwindow") {
                model.selectedSection = .protectedApps
                authenticateAndOpenMainWindow()
            }
            MenuRow(title: "Private Vault…", symbol: "lock.rectangle.stack.fill") {
                model.selectedSection = .vault
                authenticateAndOpenMainWindow()
            }
            MenuRow(title: "Settings…", symbol: "gearshape") {
                model.selectedSection = .settings
                authenticateAndOpenMainWindow()
            }
            MenuRow(title: "Check for Updates…", symbol: "arrow.triangle.2.circlepath") {
                model.checkForUpdates()
            }

            Divider()

            MenuRow(title: "Quit Privio", symbol: "power") {
                // Wymaga uwierzytelnienia, jeśli ochrona jest aktywna (sekcja 18).
                model.requestQuit()
            }
        }
        .frame(width: 300)
        .task { await vault.start() }
    }

    private var proximityRow: some View {
        let cfg = model.proximityConfig
        let active = cfg.enabled && !cfg.paused && !proximity.autoPausedNotice
        let substatus = !cfg.enabled ? "Off"
            : (proximity.autoPausedNotice ? "Auto-paused" : (cfg.paused ? "Paused" : "Armed"))
        return HStack(spacing: 10) {
            FAIcon("dot.radiowaves.left.and.right", size: 12).frame(width: 16)
                .foregroundStyle(active ? Color.privioUnlocked : Color.privioTextSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Proximity Lock")
                    .font(.privioSystem(size: 13, weight: .medium)).foregroundStyle(Color.privioTextPrimary)
                Text(LocalizedStringKey(substatus))
                    .font(.privioSystem(size: 10.5)).foregroundStyle(Color.privioTextTertiary)
            }
            Spacer()
            Text(NSLocalizedString(active ? "ON" : "OFF", comment: "Proximity switch state"))
                .font(.privioSystem(size: 10.5, weight: .semibold))
                .foregroundStyle(active ? Color.privioUnlocked : Color.privioTextTertiary)
            // Ten sam `enabled` co w oknie. Włączenie czyści też auto-pauzę/pauzę.
            Toggle("", isOn: Binding(
                get: { cfg.enabled },
                set: { on in model.setProximityConfig { $0.enabled = on; if on { $0.paused = false } } }
            ))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(.privioPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func authenticateAndOpenMainWindow() {
        Task {
            guard await model.unlockMainWindow() else { return }
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
    }
}

/// Lista aplikacji aktualnie otwartych spośród skonfigurowanych, z ich statusem
/// blokady. `model.runningApps` odpytuje system przy każdym renderze, a panel w
/// pasku menu jest budowany od nowa po każdym otwarciu, więc lista jest aktualna.
private struct OpenAppsSection: View {
    @Environment(AppModel.self) private var model
    @Binding var showAll: Bool

    var body: some View {
        let running = model.runningApps
        VStack(spacing: 0) {
            HStack {
                Text("Open apps")
                    .font(.privioSystem(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.privioTextTertiary)
                Spacer()
                if !running.isEmpty {
                    Text("\(running.count)")
                        .font(.privioSystem(size: 10.5, weight: .medium))
                        .foregroundStyle(Color.privioTextTertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if running.isEmpty {
                Text("No protected apps are open")
                    .font(.privioSystem(size: 12))
                    .foregroundStyle(Color.privioTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 8)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(running.prefix(showAll ? running.count : 3)) { snapshot in
                            HStack(spacing: 10) {
                                AppIconView(app: snapshot.app, size: 20)
                                Text(snapshot.app.displayName)
                                    .font(.privioSystem(size: 13))
                                    .foregroundStyle(Color.privioTextPrimary)
                                Spacer()
                                StatusBadge(status: model.effectiveStatus(snapshot), compact: true)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                        }
                    }
                }
                .scrollIndicators(showAll ? .automatic : .hidden)
                .frame(height: listHeight(count: running.count))

                if running.count > 3 {
                    Divider().padding(.leading, 44)
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) { showAll.toggle() }
                    } label: {
                        HStack(spacing: 7) {
                            FAIcon(showAll ? "chevron.up" : "chevron.down", size: 9)
                            Text(showAll ? NSLocalizedString("Show less", comment: "Collapse open apps")
                                         : String(format: NSLocalizedString("Show %d more", comment: "Expand open apps in menu bar"), running.count - 3))
                                .font(.privioSystem(size: 11.5, weight: .medium))
                        }
                        .foregroundStyle(Color.privioPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.bottom, 4)
    }

    /// Wysokość = liczba widocznych wierszy × 34 pt (ikona 20 pt + padding 2 × 7 pt).
    /// Rozwinięte: maks. sześć wierszy, reszta przez scroll.
    private func listHeight(count: Int) -> CGFloat {
        let rows = showAll ? min(count, 6) : min(count, 3)
        return CGFloat(rows) * 34
    }
}

private struct MenuRow: View {
    let title: LocalizedStringKey
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                FAIcon(symbol, size: 12)
                    .frame(width: 16)
                    .foregroundStyle(Color.privioTextSecondary)
                Text(title)
                    .font(.privioSystem(size: 13))
                    .foregroundStyle(Color.privioTextPrimary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(hovering ? Color.privioSurfaceSelected : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
