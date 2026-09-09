import SwiftUI
import PrivioCore

struct AboutView: View {
    @Environment(AppModel.self) private var model

    private let reasons: [(String, String)] = [
        ("touchid", "Lock any app with Touch ID"),
        ("clock", "Lock after inactivity"),
        ("power", "Auto-quit for extra privacy"),
        ("macwindow", "Works in the background"),
        ("bolt.shield", "Secure & lightweight"),
        ("apple.logo", "Built for macOS"),
    ]

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    private func noteLine(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            FAIcon(symbol, size: 13)
                .foregroundStyle(Color.privioTextSecondary)
                .frame(width: 18)
            Text(text)
                .font(.privioSystem(size: 11.5))
                .foregroundStyle(Color.privioTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func privacyLine(_ symbol: String, _ title: LocalizedStringKey, _ subtitle: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            FAIcon(symbol, size: 15)
                .foregroundStyle(Color.privioUnlocked)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.privioSystem(size: 13.5, weight: .medium)).foregroundStyle(Color.privioTextPrimary)
                Text(subtitle).font(.privioSystem(size: 11.5)).foregroundStyle(Color.privioTextTertiary)
            }
            Spacer()
        }
    }

    private func contactLine(_ symbol: String, _ label: LocalizedStringKey, _ display: String, _ url: String) -> some View {
        HStack(spacing: 10) {
            FAIcon(symbol)
                .foregroundStyle(Color.privioPrimary)
                .font(.privioSystem(size: 14))
                .frame(width: 20)
            Text(label)
                .font(.privioSystem(size: 13, weight: .medium))
                .foregroundStyle(Color.privioTextSecondary)
                .frame(width: 90, alignment: .leading)
            if let link = URL(string: url) {
                Link(display, destination: link)
                    .font(.privioSystem(size: 13))
                    .foregroundStyle(Color.privioPrimary)
            } else {
                Text(display).font(.privioSystem(size: 13)).foregroundStyle(Color.privioTextPrimary)
            }
            Spacer()
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: PrivioLayout.sectionSpacing) {
                VStack(spacing: 14) {
                    PrivioLogo().frame(width: 84, height: 104)
                    VStack(spacing: 4) {
                        Text("Privio")
                            .font(.privioSystem(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.privioTextPrimary)
                        Text("Your Mac. Your privacy. Your rules.")
                            .font(.privioSystem(size: 16, weight: .semibold))
                            .foregroundStyle(Color.privioPrimary)
                            .multilineTextAlignment(.center)
                        Text("Keep prying eyes out of your email, conversations and photos. Choose which apps to lock and unlock them when you need them.")
                            .font(.privioSystem(size: 14))
                            .foregroundStyle(Color.privioTextSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 440)
                            .padding(.top, 2)
                        Text("Version \(appVersion)")
                            .font(.privioSystem(size: 12))
                            .foregroundStyle(Color.privioTextTertiary)
                            .padding(.top, 4)
                        Button { model.checkForUpdates() } label: {
                            HStack(spacing: 5) {
                                FAIcon("arrow.triangle.2.circlepath")
                                Text("Check for Updates…")
                            }
                            .font(.privioSystem(size: 12.5, weight: .medium))
                            .foregroundStyle(Color.privioPrimary)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                }
                .padding(.top, 36)

                LicenseCard()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Why Privio?")
                        .font(.privioSystem(size: 13, weight: .semibold))
                        .foregroundStyle(Color.privioTextSecondary)
                    ForEach(reasons, id: \.1) { symbol, text in
                        HStack(spacing: 12) {
                            FAIcon(symbol, size: 15)
                                .foregroundStyle(Color.privioPrimary)
                                .frame(width: 24)
                            Text(LocalizedStringKey(text))
                                .font(.privioSystem(size: 14))
                                .foregroundStyle(Color.privioTextPrimary)
                            Spacer()
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.privioSurface)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.privioSeparator, lineWidth: 1)))

                VStack(alignment: .leading, spacing: 14) {
                    Text("Privacy")
                        .font(.privioSystem(size: 13, weight: .semibold))
                        .foregroundStyle(Color.privioTextSecondary)
                    privacyLine("eye.slash.fill", "No analytics", "Privio never measures how you use it.")
                    privacyLine("nosign", "No telemetry", "Privio sends no usage data to us.")
                    privacyLine("icloud.slash", "No cloud sync", "All configuration stays local.")
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.privioSurface)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.privioSeparator, lineWidth: 1)))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Good to know")
                        .font(.privioSystem(size: 13, weight: .semibold))
                        .foregroundStyle(Color.privioTextSecondary)
                    noteLine("bell.badge",
                             "macOS notification previews may still reveal content from a protected app. Turn them off in System Settings › Notifications › Show Previews.")
                    noteLine("externaldrive",
                             "Privio protects access to an app’s interface - not the app’s files, databases or exports on disk.")
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.privioSurface)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.privioSeparator, lineWidth: 1)))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Contact")
                        .font(.privioSystem(size: 13, weight: .semibold))
                        .foregroundStyle(Color.privioTextSecondary)
                    contactLine("globe", "Website", "priviolock.com", "https://priviolock.com")
                    Divider().overlay(Color.privioSeparator)
                    contactLine("envelope", "Contact", "contact@priviolock.com", "mailto:contact@priviolock.com")
                    Divider().overlay(Color.privioSeparator)
                    contactLine("lifepreserver", "Support", "support@priviolock.com", "mailto:support@priviolock.com")
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.privioSurface)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.privioSeparator, lineWidth: 1)))

                HStack(spacing: 18) {
                    Label { Text("Your data stays on your Mac") } icon: { FAIcon("lock.fill") }
                    Label { Text("No tracking. No sync. Just privacy.") } icon: { FAIcon("checkmark.shield") }
                }
                .font(.privioSystem(size: 12))
                .foregroundStyle(Color.privioTextSecondary)
                .padding(.bottom, 30)
            }
            .padding(.horizontal, PrivioLayout.pagePadding)
            .frame(maxWidth: .infinity)
        }
    }
}
