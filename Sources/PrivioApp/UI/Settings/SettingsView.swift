import SwiftUI
import PrivioCore

/// Ustawienia (scalone: dawne General + Settings) - sekcja 20.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showUninstall = false
    @State private var showClearPhotos = false
    @State private var showCameraDenied = false

    /// Zmiana języka zapisuje wybór i restartuje Privio (język ładuje się na starcie).
    private var languageBinding: Binding<AppLanguage> {
        Binding(get: { AppLanguage.current }, set: { AppLanguage.select($0) })
    }

    /// Motyw jasny/ciemny/systemowy - stosowany natychmiast (bez restartu).
    private var themeBinding: Binding<AppTheme> {
        Binding(get: { AppTheme.current }, set: { AppTheme.select($0) })
    }

    var body: some View {
        SettingsScreen(title: "Settings") {
            SecurityStatusCard()

            SettingsCard("Protection") {
                SettingsToggleRow(
                    label: "Privio is active",
                    subtitle: "Master switch for all protection.",
                    isOn: Binding(get: { model.state.protectionActive },
                                  set: { model.setProtectionActive($0) }))   // wyłączenie → auth
                Divider().overlay(Color.privioSeparator)
                SettingsToggleRow(
                    label: "Start Privio at login",
                    subtitle: "Protection begins with your session.",
                    isOn: Binding(get: { model.state.configuration.startAtLogin },
                                  set: { model.setStartAtLogin($0) }))
                Divider().overlay(Color.privioSeparator)
                SettingsToggleRow(label: "Show menu bar icon", isOn: cfgBool(\.showMenuBarIcon))
            }

            SettingsCard("Language") {
                HStack {
                    Text("Interface language")
                        .font(.privioSystem(size: 13.5))
                        .foregroundStyle(Color.privioTextPrimary)
                    Spacer()
                    Picker("", selection: languageBinding) {
                        ForEach(AppLanguage.allCases) { Text(LocalizedStringKey($0.displayName)).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).tint(.privioPrimary).fixedSize()
                }
                Text("Default follows your Mac’s language. Changing this restarts Privio.")
                    .font(.privioSystem(size: 11.5)).foregroundStyle(Color.privioTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SettingsCard("Appearance") {
                HStack {
                    Text("Theme")
                        .font(.privioSystem(size: 13.5))
                        .foregroundStyle(Color.privioTextPrimary)
                    Spacer()
                    Picker("", selection: themeBinding) {
                        ForEach(AppTheme.allCases) { Text(LocalizedStringKey($0.titleKey)).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).tint(.privioPrimary).fixedSize()
                }
                Text("Light or dark. “System” follows your Mac’s appearance.")
                    .font(.privioSystem(size: 11.5)).foregroundStyle(Color.privioTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SettingsCard("Lock triggers") {
                SettingsToggleRow(label: "Lock protected apps after screen lock",
                                  isOn: cfgBool(\.lockAllAfterScreenLock))
                Divider().overlay(Color.privioSeparator)
                SettingsToggleRow(label: "Lock protected apps after sleep",
                                  isOn: cfgBool(\.lockAllAfterSleep))
            }

            SettingsCard("Defaults for new apps") {
                authMethodRow
                Divider().overlay(Color.privioSeparator)
                lockPickerRow
                Divider().overlay(Color.privioSeparator)
                quitPickerRow
            }

            SettingsCard("Failed unlock attempts") {
                SettingsToggleRow(
                    label: "Take a photo after unsuccessful authentication",
                    subtitle: "Opt-in. Includes canceled prompts; photos stay in Privio and the oldest are deleted after 20 images.",
                    isOn: Binding(
                        get: { model.state.configuration.captureFailedAttempts },
                        set: { enabled in
                            Task {
                                if !(await model.setCaptureFailedAttempts(enabled)) {
                                    showCameraDenied = true
                                }
                            }
                        }
                    )
                )
                Divider().overlay(Color.privioSeparator)
                HStack {
                    Button("View Photos in Activity") { model.selectedSection = .activity }
                    Spacer()
                    Button("Delete All Photos", role: .destructive) { showClearPhotos = true }
                }
                .font(.privioSystem(size: 12.5, weight: .medium))
            }

            SettingsCard("Advanced") {
                Button { model.checkForUpdates() } label: {
                    HStack(spacing: 6) {
                        FAIcon("arrow.triangle.2.circlepath")
                        Text("Check for Updates…")
                    }
                    .font(.privioSystem(size: 13.5, weight: .medium))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                Divider().overlay(Color.privioSeparator)
                Button(role: .destructive) { showUninstall = true } label: {
                    HStack(spacing: 6) {
                        FAIcon("trash")
                        Text("Uninstall Privio…")
                    }
                    .font(.privioSystem(size: 13.5, weight: .medium))
                    .foregroundStyle(Color.privioDanger)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("Requires Touch ID. Stops protection, removes Privio’s settings and license, and moves Privio to the Trash. Your protected apps and their data are not touched.")
                    .font(.privioSystem(size: 11.5)).foregroundStyle(Color.privioTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .alert("Uninstall Privio?", isPresented: $showUninstall) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall", role: .destructive) { model.uninstall() }
        } message: {
            Text("This stops protection, removes Privio’s settings and license, and moves Privio to the Trash. It requires Touch ID. Your protected apps and their data are not affected.")
        }
        .alert("Camera Access Required", isPresented: $showCameraDenied) {
            Button("Cancel", role: .cancel) {}
            Button("Open Camera Settings") { model.openCameraPrivacySettings() }
        } message: {
            Text("macOS can’t ask again after access was denied. Open Camera settings and enable Privio, then turn this option on again.")
        }
        .alert("Delete all failed-attempt photos?", isPresented: $showClearPhotos) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) { model.clearFailedAttemptPhotos() }
        } message: {
            Text("This permanently deletes locally stored failed-attempt photos.")
        }
    }

    // MARK: - Wiersze

    private var authMethodRow: some View {
        HStack {
            Text("Default unlock method").font(.privioSystem(size: 13.5)).foregroundStyle(Color.privioTextPrimary)
            Spacer()
            Picker("", selection: Binding(
                get: { AuthMethodChoice(configuration: model.state.configuration) },
                set: { choice in
                    var c = model.state.configuration
                    choice.apply(to: &c)
                    model.updateConfiguration(c)
                })) {
                ForEach(AuthMethodChoice.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).tint(.privioPrimary).fixedSize()
        }
    }

    private var lockPickerRow: some View {
        HStack {
            Text("Default lock timeout").font(.privioSystem(size: 13.5)).foregroundStyle(Color.privioTextPrimary)
            Spacer()
            Picker("", selection: Binding(
                get: { LockTimeoutPreset.from(seconds: model.state.configuration.defaultLockTimeout) },
                set: { preset in
                    var c = model.state.configuration
                    c.defaultLockTimeout = preset.seconds
                    model.updateConfiguration(c)
                })) {
                ForEach(LockTimeoutPreset.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).tint(.privioPrimary).fixedSize()
        }
    }

    private var quitPickerRow: some View {
        HStack {
            Text("Default quit timeout").font(.privioSystem(size: 13.5)).foregroundStyle(Color.privioTextPrimary)
            Spacer()
            Picker("", selection: Binding(
                get: { QuitTimeoutPreset.from(seconds: model.state.configuration.defaultQuitTimeout) },
                set: { preset in
                    var c = model.state.configuration
                    c.defaultQuitTimeout = preset.seconds
                    model.updateConfiguration(c)
                })) {
                ForEach(QuitTimeoutPreset.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).tint(.privioPrimary).fixedSize()
        }
    }

    private func cfgBool(_ keyPath: WritableKeyPath<AppConfiguration, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.state.configuration[keyPath: keyPath] },
            set: { newValue in
                var c = model.state.configuration
                c[keyPath: keyPath] = newValue
                model.updateConfiguration(c)
            })
    }
}
