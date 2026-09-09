import SwiftUI
import PrivioCore

/// Ekran modułu „Zasłona prywatności" (Privacy Curtain) - sytuacyjne ukrywanie treści
/// chronionych aplikacji, niezależne od blokady Touch ID. Konfiguracja raz, codzienne
/// użycie to jedynie ON/OFF (jak Airplane Mode / Do Not Disturb).
struct PrivacyCurtainView: View {
    @Environment(AppModel.self) private var model

    private var config: AppConfiguration { model.state.configuration }

    var body: some View {
        SettingsScreen(title: "Privacy Curtain") {
            SettingsCard {
                SettingsToggleRow(
                    label: "Privacy Curtain",
                    subtitle: "Hide protected app windows until you reveal them.",
                    isOn: Binding(get: { model.privacyModeEnabled },
                                  set: { model.setPrivacyModeEnabled($0) }))
                Divider().overlay(Color.privioSeparator)
                Text("Turn it on in public places - a train, a café, a coworking space. Your protected apps stay usable; their windows are simply hidden until you reveal them. Configure once, toggle daily.")
                    .font(.privioSystem(size: 12))
                    .foregroundStyle(Color.privioTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SettingsCard("Effect") {
                // Wariant efektu
                VStack(alignment: .leading, spacing: 8) {
                    Text("Style")
                        .font(.privioSystem(size: 13.5))
                        .foregroundStyle(Color.privioTextPrimary)
                    Picker("", selection: modeBinding) {
                        Text("Spotlight").tag(PrivacyCurtainMode.spotlight)
                        Text("Privacy filter").tag(PrivacyCurtainMode.tint)
                        Text("Blur").tag(PrivacyCurtainMode.blur)
                    }
                    .labelsHidden().pickerStyle(.segmented)
                    Text(modeHint)
                        .font(.privioSystem(size: 11.5))
                        .foregroundStyle(Color.privioTextTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().overlay(Color.privioSeparator)

                // Zakres
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Applies to")
                            .font(.privioSystem(size: 13.5))
                            .foregroundStyle(Color.privioTextPrimary)
                        Text("Whole screen, or only protected apps.")
                            .font(.privioSystem(size: 11.5))
                            .foregroundStyle(Color.privioTextTertiary)
                    }
                    Spacer()
                    Picker("", selection: scopeBinding) {
                        Text("Protected apps").tag(PrivacyCurtainScope.protectedApps)
                        Text("Whole screen").tag(PrivacyCurtainScope.fullScreen)
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }

                Divider().overlay(Color.privioSeparator)

                // Intensywność
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Dimming")
                            .font(.privioSystem(size: 13.5))
                            .foregroundStyle(Color.privioTextPrimary)
                        Spacer()
                        Text("\(Int((config.privacyCurtainIntensity * 100).rounded()))%")
                            .font(.privioSystem(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(Color.privioTextTertiary)
                    }
                    Slider(value: intensityBinding, in: AppConfiguration.curtainIntensityRange)
                        .tint(.privioPrimary)
                }

                // Kształt i rozmiar latarki - tylko w trybie spotlight
                if config.privacyCurtainMode == .spotlight {
                    Divider().overlay(Color.privioSeparator)
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Flashlight shape")
                                .font(.privioSystem(size: 13.5))
                                .foregroundStyle(Color.privioTextPrimary)
                            Text("Area revealed around the cursor.")
                                .font(.privioSystem(size: 11.5))
                                .foregroundStyle(Color.privioTextTertiary)
                        }
                        Spacer()
                        Picker("", selection: shapeBinding) {
                            Text("Circle").tag(PrivacyCurtainSpotlightShape.circle)
                            Text("Wide").tag(PrivacyCurtainSpotlightShape.ellipse)
                            Text("Rectangle").tag(PrivacyCurtainSpotlightShape.rectangle)
                        }
                        .labelsHidden().pickerStyle(.menu).fixedSize()
                    }
                    Divider().overlay(Color.privioSeparator)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Flashlight size")
                                .font(.privioSystem(size: 13.5))
                                .foregroundStyle(Color.privioTextPrimary)
                            Spacer()
                            Text("\(Int(config.privacyCurtainSpotlightRadius.rounded())) pt")
                                .font(.privioSystem(size: 12, weight: .medium).monospacedDigit())
                                .foregroundStyle(Color.privioTextTertiary)
                        }
                        Slider(value: radiusBinding, in: AppConfiguration.spotlightRadiusRange)
                            .tint(.privioPrimary)
                    }
                }
            }

            SettingsCard("Shortcuts") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Toggle Privacy Curtain")
                            .font(.privioSystem(size: 13.5))
                            .foregroundStyle(Color.privioTextPrimary)
                        Text("Optional global shortcut")
                            .font(.privioSystem(size: 11.5))
                            .foregroundStyle(Color.privioTextTertiary)
                    }
                    Spacer()
                    ShortcutRecorderField(
                        identifier: config.privacyModeShortcut,
                        allowsClearing: true,
                        conflictingIdentifier: config.privacyRevealHoldShortcut
                    ) { value in updating { $0.privacyModeShortcut = value } }
                }
                Divider().overlay(Color.privioSeparator)
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Temporary Reveal")
                            .font(.privioSystem(size: 13.5))
                            .foregroundStyle(Color.privioTextPrimary)
                        Text("Hold the shortcut to reveal")
                            .font(.privioSystem(size: 11.5))
                            .foregroundStyle(Color.privioTextTertiary)
                    }
                    Spacer()
                    ShortcutRecorderField(
                        identifier: config.privacyRevealHoldShortcut,
                        conflictingIdentifier: config.privacyModeShortcut
                    ) { value in
                        guard let value else { return }
                        updating { $0.privacyRevealHoldShortcut = value }
                    }
                }
            }
        }
    }

    private var modeHint: LocalizedStringKey {
        switch config.privacyCurtainMode {
        case .blur:      return "Blurs protected content so it can’t be read over your shoulder."
        case .spotlight: return "Darkens the screen and reveals only a flashlight around the cursor."
        case .tint:      return "Dims and lowers contrast toward the edges so it’s hard to read from the side. A software effect - it can’t fully match a physical privacy filter."
        }
    }

    // MARK: - Bindings

    private func updating(_ mutate: @escaping (inout AppConfiguration) -> Void) {
        var c = model.state.configuration
        mutate(&c)
        model.updateConfiguration(c)
    }

    private var modeBinding: Binding<PrivacyCurtainMode> {
        Binding(get: { config.privacyCurtainMode },
                set: { value in updating { $0.privacyCurtainMode = value } })
    }

    private var scopeBinding: Binding<PrivacyCurtainScope> {
        Binding(get: { config.privacyCurtainScope },
                set: { value in updating { $0.privacyCurtainScope = value } })
    }

    private var intensityBinding: Binding<Double> {
        Binding(get: { config.privacyCurtainIntensity },
                set: { value in updating { $0.privacyCurtainIntensity = value } })
    }

    private var radiusBinding: Binding<Double> {
        Binding(get: { config.privacyCurtainSpotlightRadius },
                set: { value in updating { $0.privacyCurtainSpotlightRadius = value } })
    }

    private var shapeBinding: Binding<PrivacyCurtainSpotlightShape> {
        Binding(get: { config.privacyCurtainSpotlightShape },
                set: { value in updating { $0.privacyCurtainSpotlightShape = value } })
    }

}
