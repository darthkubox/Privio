import SwiftUI
import PrivioCore

/// Panel konfiguracji wybranej apki (sekcja 16). Zmiany od razu trafiają przez
/// seam do enforcementu (model.updateApp).
struct AppDetailPanel: View {
    @Environment(AppModel.self) private var model
    let snapshot: ProtectedAppSnapshot

    /// Wartość quit oczekująca na potwierdzenie (ostrzeżenie o utracie danych).
    @State private var pendingQuit: QuitTimeoutPreset?
    @State private var showQuitWarning = false

    private var app: ProtectedApp { snapshot.app }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PrivioLayout.sectionSpacing) {
                header

                section("Lock Settings") {
                    pickerRow("Lock after inactivity",
                              selection: lockBinding,
                              options: LockTimeoutPreset.allCases,
                              title: \.title)
                    Divider().overlay(Color.privioSeparator)
                    pickerRow("Quit after inactivity",
                              selection: quitBinding,
                              options: QuitTimeoutPreset.allCases,
                              title: \.title)
                    if let warning = app.timeoutWarning {
                        warningRow(LocalizedStringKey(warning))
                    }
                    if app.quitPreset != .never {
                        Divider().overlay(Color.privioSeparator)
                        toggleRow("Force quit if it doesn’t respond", binding(\.forceQuitIfUnresponsive))
                        Text("If \(app.displayName) won’t close on its own, Privio force‑quits it - unsaved work may be lost.")
                            .font(.privioSystem(size: 11.5))
                            .foregroundStyle(Color.privioTextTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                section("Authentication") {
                    pickerRow("Unlock with",
                              selection: authMethodBinding,
                              options: AuthMethodChoice.allCases,
                              title: \.title)
                    Text(LocalizedStringKey(authMethodBinding.wrappedValue.footnote))
                        .font(.privioSystem(size: 11.5))
                        .foregroundStyle(Color.privioTextTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                section("Additional") {
                    checkboxRow("Lock after screen lock", binding(\.lockAfterScreenLock))
                    checkboxRow("Lock after sleep", binding(\.lockAfterSleep))
                    Divider().overlay(Color.privioSeparator)
                    notificationSettingsRow
                }

                Spacer(minLength: 12)
                removeButton
            }
            .padding(.horizontal, PrivioLayout.pagePadding)
            .padding(.top, PrivioLayout.pagePadding)
            .padding(.bottom, PrivioLayout.pagePadding)
        }
        .alert("Enable auto-quit?", isPresented: $showQuitWarning) {
            Button("Cancel", role: .cancel) { pendingQuit = nil }
            Button("Enable auto-quit", role: .destructive) {
                if let p = pendingQuit { applyQuit(p) }
            }
        } message: {
            Text("Privio will close \(app.displayName) automatically after inactivity. Any unsaved changes in \(app.displayName) may be lost - especially with “Force quit if it doesn’t respond” turned on. Are you sure you want to enable auto-quit?")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            AppIconView(app: app, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.displayName)
                    .font(.privioSystem(size: 20, weight: .bold))
                    .foregroundStyle(Color.privioTextPrimary)
                Text(app.bundleIdentifier)
                    .font(.privioSystem(size: 12))
                    .foregroundStyle(Color.privioTextTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                StatusBadge(status: model.effectiveStatus(snapshot))
                if model.effectiveStatus(snapshot) == .locked {
                    Button { model.requestAuthentication(for: app) } label: {
                        HStack(spacing: 5) {
                            FAIcon("touchid")
                            Text(NSLocalizedString("Unlock", comment: "Unlock protected app"))
                        }
                        .font(.privioSystem(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(PrivioGradient.brand))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Sekcje / wiersze

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.privioSystem(size: 12, weight: .semibold))
                .foregroundStyle(Color.privioTextSecondary)
                .textCase(.uppercase)
                .padding(.bottom, 8)
            VStack(spacing: PrivioLayout.cardSpacing) {
                content()
            }
            .padding(PrivioLayout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.privioSurface)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.privioSeparator, lineWidth: 1))
            )
        }
    }

    private func pickerRow<Option: Hashable & Identifiable>(
        _ label: LocalizedStringKey,
        selection: Binding<Option>,
        options: [Option],
        title: KeyPath<Option, String>
    ) -> some View {
        HStack {
            Text(label)
                .font(.privioSystem(size: 13.5))
                .foregroundStyle(Color.privioTextPrimary)
            Spacer()
            Picker("", selection: selection) {
                ForEach(options) { option in
                    Text(LocalizedStringKey(option[keyPath: title])).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(.privioPrimary)
            .fixedSize()
        }
    }

    private func toggleRow(_ label: LocalizedStringKey, _ isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(.privioSystem(size: 13.5))
                .foregroundStyle(Color.privioTextPrimary)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(.privioPrimary)
        }
    }

    private func checkboxRow(_ label: LocalizedStringKey, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label)
                .font(.privioSystem(size: 13.5))
                .foregroundStyle(Color.privioTextPrimary)
        }
        .toggleStyle(.checkbox)
        .tint(.privioPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func warningRow(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            FAIcon("exclamationmark.triangle.fill")
                .foregroundStyle(Color.privioDanger)
                .font(.privioSystem(size: 12))
            Text(text)
                .font(.privioSystem(size: 12))
                .foregroundStyle(Color.privioTextSecondary)
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    /// Skrót do systemowych ustawień powiadomień danej apki - powiadomienia mogą
    /// pokazać treść chronionej apki (podglądy) mimo blokady; stąd szybkie przejście.
    private var notificationSettingsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                model.openNotificationSettings(for: app)
            } label: {
                HStack(spacing: 6) {
                    FAIcon("bell.badge")
                    Text("Notification settings…")
                    Spacer()
                    FAIcon("arrow.up.right", size: 11)
                        .foregroundStyle(Color.privioTextTertiary)
                }
                .font(.privioSystem(size: 13.5, weight: .medium))
                .foregroundStyle(Color.privioPrimary)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("Notifications can reveal content from \(app.displayName) even while it’s locked. Open macOS notification settings to turn them off.")
                .font(.privioSystem(size: 11.5))
                .foregroundStyle(Color.privioTextTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var removeButton: some View {
        Button(role: .destructive) {
            model.removeApp(app)
        } label: {
            HStack(spacing: 6) {
                FAIcon("trash")
                Text("Remove App")
            }
            .font(.privioSystem(size: 13, weight: .medium))
            .foregroundStyle(Color.privioDanger)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - Bindings (zapis przez seam)

    private func binding<T>(_ keyPath: WritableKeyPath<ProtectedApp, T>) -> Binding<T> {
        Binding(
            get: { app[keyPath: keyPath] },
            set: { newValue in
                var updated = app
                updated[keyPath: keyPath] = newValue
                model.updateApp(updated)
            }
        )
    }

    private var lockBinding: Binding<LockTimeoutPreset> {
        Binding(
            get: { LockTimeoutPreset.from(seconds: app.lockAfterInactivity) },
            set: { preset in
                var updated = app
                updated.lockAfterInactivity = preset.seconds
                model.updateApp(updated)
            }
        )
    }

    private var quitBinding: Binding<QuitTimeoutPreset> {
        Binding(
            get: { pendingQuit ?? QuitTimeoutPreset.from(seconds: app.quitAfterInactivity) },
            set: { preset in
                // Każdy wybór auto‑quit (poza „Never") → ostrzeżenie o możliwej
                // utracie niezapisanych zmian i potwierdzenie. „Never" (wyłączenie)
                // stosujemy od razu, bez pytania.
                if preset != .never {
                    pendingQuit = preset
                    showQuitWarning = true
                } else {
                    applyQuit(preset)
                }
            }
        )
    }

    private func applyQuit(_ preset: QuitTimeoutPreset) {
        pendingQuit = nil
        var updated = app
        updated.quitAfterInactivity = preset.seconds
        model.updateApp(updated)
    }

    /// Wybór metody odblokowania per aplikacja.
    private var authMethodBinding: Binding<AuthMethodChoice> {
        Binding(
            get: { AuthMethodChoice(app: app) },
            set: { choice in
                var updated = app
                choice.apply(to: &updated)
                model.updateApp(updated)
            }
        )
    }
}

/// Metoda odblokowania wybierana per aplikacja (sekcja 11).
enum AuthMethodChoice: String, CaseIterable, Identifiable, Hashable {
    case touchIDOrPassword
    case touchIDOnly
    case passwordOnly

    var id: Self { self }

    var title: String {
        switch self {
        case .touchIDOrPassword: return "Touch ID or password"
        case .touchIDOnly:       return "Touch ID only"
        case .passwordOnly:      return "Password only"
        }
    }

    var footnote: String {
        switch self {
        case .touchIDOrPassword:
            return "Falls back to your Mac password - e.g. with the lid closed."
        case .touchIDOnly:
            return "Requires Touch ID; can’t unlock when Touch ID is unavailable."
        case .passwordOnly:
            return "Always asks for your Mac account password; Touch ID is not used."
        }
    }

    init(app: ProtectedApp) {
        if !app.requireTouchID {
            self = .passwordOnly
        } else {
            self = app.allowPasswordFallback ? .touchIDOrPassword : .touchIDOnly
        }
    }

    init(configuration: AppConfiguration) {
        if !configuration.defaultRequireTouchID {
            self = .passwordOnly
        } else {
            self = configuration.defaultAllowPasswordFallback ? .touchIDOrPassword : .touchIDOnly
        }
    }

    func apply(to app: inout ProtectedApp) {
        app.requireTouchID = self != .passwordOnly
        app.allowPasswordFallback = self != .touchIDOnly
    }

    func apply(to configuration: inout AppConfiguration) {
        configuration.defaultRequireTouchID = self != .passwordOnly
        configuration.defaultAllowPasswordFallback = self != .touchIDOnly
    }
}
