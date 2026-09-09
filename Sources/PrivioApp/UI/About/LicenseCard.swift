import SwiftUI
import PrivioCore

/// Karta licencji w About: status Free/Pro oraz aktywacja Pro przez LOKALNĄ
/// weryfikację klucza (bez konta, bez aktywacji sieciowej).
struct LicenseCard: View {
    @Environment(AppModel.self) private var model
    @State private var licenseKey = ""
    @State private var showInvalid = false
    @State private var showAgreement = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.isPro {
                proContent
            } else {
                freeContent
            }
            Divider().overlay(Color.privioSeparator)
            Button("View License & Terms") { showAgreement = true }
                .buttonStyle(.plain)
                .font(.privioSystem(size: 12))
                .foregroundStyle(Color.privioPrimary)
        }
        .sheet(isPresented: $showAgreement) {
            LicenseAgreementView(requireAcceptance: false).privioSheetCloseButton()
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.privioSurface)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.privioSeparator, lineWidth: 1)))
    }

    private var proContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                FAIcon("checkmark.seal.fill").foregroundStyle(Color.privioUnlocked)
                Text("Privio Pro").font(.privioSystem(size: 16, weight: .bold))
                    .foregroundStyle(Color.privioTextPrimary)
            }
            Text("License verified locally. No account or online activation required.")
                .font(.privioSystem(size: 12)).foregroundStyle(Color.privioTextSecondary)
            if let info = model.licenseInfo {
                Text("License \(info.licenseID)")
                    .font(.privioSystem(size: 11)).foregroundStyle(Color.privioTextTertiary)
            }
            Button("Remove license") { model.removeLicense() }
                .buttonStyle(.plain)
                .font(.privioSystem(size: 12))
                .foregroundStyle(Color.privioDanger)
                .padding(.top, 2)
        }
    }

    private var freeContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Privio Free").font(.privioSystem(size: 16, weight: .bold))
                    .foregroundStyle(Color.privioTextPrimary)
                Spacer()
            }
            Text("Enter a Pro license key to unlock Pro features. It’s verified entirely on your Mac - no account, no online activation.")
                .font(.privioSystem(size: 12)).foregroundStyle(Color.privioTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                TextField("License key", text: $licenseKey)
                    .textFieldStyle(.plain)
                    .font(.privioSystem(size: 12.5, design: .monospaced))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.privioBackgroundRaised)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.privioSeparator, lineWidth: 1)))
                Button(action: activate) {
                    Text("Activate Pro")
                        .font(.privioSystem(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(PrivioGradient.brand))
                }
                .buttonStyle(.plain)
                .disabled(licenseKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if showInvalid {
                Label("That license key isn’t valid.", fa: "exclamationmark.triangle.fill")
                    .font(.privioSystem(size: 11.5)).foregroundStyle(Color.privioDanger)
            }
        }
    }

    private func activate() {
        switch model.activatePro(licenseKey) {
        case .activated:
            showInvalid = false
            licenseKey = ""
        case .invalid:
            showInvalid = true
        }
    }
}
