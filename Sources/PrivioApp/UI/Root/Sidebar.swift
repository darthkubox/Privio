import SwiftUI
import PrivioCore

struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(VaultController.self) private var vault

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            // Logo + wordmark
            HStack(spacing: 10) {
                PrivioLogo()
                    .frame(width: 26, height: 32)
                Text("Privio")
                    .font(.privioSystem(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.privioTextPrimary)
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 20)

            // Nawigacja
            VStack(spacing: 2) {
                ForEach(SidebarSection.visibleCases) { section in
                    SidebarButton(
                        section: section,
                        isSelected: model.selectedSection == section,
                        moduleIsActive: moduleStatus(for: section),
                        vaultState: vaultState(for: section),
                        notificationCount: section == .activity ? model.unreadSecurityEventCount : 0
                    ) {
                        model.selectedSection = section
                    }
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 12)

            // Stopka: status ochrony + autostart (mockup)
            SidebarFooter()
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.privioBackgroundRaised)
    }

    /// `nil` oznacza zwykłą sekcję nawigacji, która nie reprezentuje modułu.
    private func moduleStatus(for section: SidebarSection) -> Bool? {
        switch section {
        case .protectedApps:
            return model.state.protectionActive && model.state.configuration.appBlockingEnabled
        case .websites:
            return model.state.protectionActive && model.state.configuration.websiteBlockingEnabled
        case .privacyCurtain:
            return model.state.configuration.privacyModeEnabled
        case .vault:
            return vault.isEnabled
        case .proximity:
            let p = model.state.configuration.proximity
            return p.enabled && !p.paused && !p.trustedDeviceIDs.isEmpty
        default:
            return nil
        }
    }

    private func vaultState(for section: SidebarSection) -> VaultStatusSymbol.State? {
        guard section == .vault else { return nil }
        if vault.isUnlocked { return .unlocked }
        return vault.isConfigured ? .locked : .neutral
    }
}

private struct SidebarButton: View {
    let section: SidebarSection
    let isSelected: Bool
    let moduleIsActive: Bool?
    let vaultState: VaultStatusSymbol.State?
    let notificationCount: Int
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                if let vaultState {
                    VaultStatusSymbol(state: vaultState)
                        .frame(width: 17, height: 17)
                        .frame(width: 20)
                } else {
                    FAIcon(section.symbol, size: 14)
                        .frame(width: 20)
                }
                Text(LocalizedStringKey(section.title))
                    .font(.privioSystem(size: 13.5, weight: isSelected ? .semibold : .medium))
                Spacer(minLength: 0)
                if notificationCount > 0 {
                    HStack(spacing: 3) {
                        FAIcon("bell.fill", size: 8)
                        Text("\(min(notificationCount, 99))")
                            .font(.privioSystem(size: 9, weight: .bold).monospacedDigit())
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 6)
                    .frame(height: 17)
                    .background(Capsule().fill(Color.privioDanger))
                    .accessibilityLabel("\(notificationCount) security alerts")
                }
                if let moduleIsActive {
                    Circle()
                        .fill(moduleIsActive ? Color.green : Color.privioTextTertiary.opacity(0.55))
                        .frame(width: 7, height: 7)
                        .overlay {
                            if moduleIsActive {
                                Circle().stroke(Color.green.opacity(0.28), lineWidth: 3)
                            }
                        }
                        .accessibilityLabel(moduleIsActive ? "Active" : "Inactive")
                }
            }
            .foregroundStyle(isSelected ? Color.white : Color.privioTextSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(background)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var background: Color {
        if isSelected { return .privioPrimary }
        return hovering ? .privioSurfaceSelected : .clear
    }
}

private struct SidebarFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                FAIcon(model.state.protectionActive
                      ? "checkmark.shield.fill" : "shield.slash.fill")
                    .foregroundStyle(model.state.protectionActive ? Color.privioPrimary : Color.privioTextTertiary)
                    .font(.privioSystem(size: 15, weight: .semibold))
                Text(LocalizedStringKey(model.state.protectionActive ? "Privio is Active" : "Privio is Off"))
                    .font(.privioSystem(size: 13, weight: .semibold))
                    .foregroundStyle(Color.privioTextPrimary)
            }

            HStack {
                Text("Protection")
                    .font(.privioSystem(size: 12.5))
                    .foregroundStyle(Color.privioTextSecondary)
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
                    get: { model.state.protectionActive },
                    set: { model.setProtectionActive($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(.privioPrimary)
            }

            HStack {
                Text("Autostart at login")
                    .font(.privioSystem(size: 12.5))
                    .foregroundStyle(Color.privioTextSecondary)
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
                    get: { model.state.configuration.startAtLogin },
                    set: { model.setStartAtLogin($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(.privioPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.privioSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.privioSeparator, lineWidth: 1)
                )
        )
    }
}
