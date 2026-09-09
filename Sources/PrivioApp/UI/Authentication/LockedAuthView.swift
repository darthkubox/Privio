import SwiftUI
import PrivioCore

/// Okno uwierzytelnienia (sekcja 17): ciemna, granatowa karta jak w mockupie.
///
/// WAŻNE: to NIE jest fałszywy dialog biometrii. Okno tylko wyjaśnia, dlaczego
/// prosimy o uwierzytelnienie. Realna biometria pochodzi z LocalAuthentication /
/// systemu (podłączenie w Fazie 5). W Fazie 1 „Authenticate" wywołuje zaślepkę.
struct LockedAuthView: View {
    let app: ProtectedApp
    var allowPasswordFallback: Bool
    let onAuthenticate: () -> Void
    let onUsePassword: () -> Void
    let onCancel: () -> Void

    @State private var didAutoStart = false

    var body: some View {
        VStack(spacing: 20) {
            PrivioLogo(fill: .solid(.white.opacity(0.95)))
                .frame(width: 40, height: 50)

            VStack(spacing: 6) {
                Text("\(app.displayName) is Locked")
                    .font(.privioSystem(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                Text("Touch ID to unlock")
                    .font(.privioSystem(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Button(action: onAuthenticate) {
                FAIcon("touchid", size: 46)
                    .foregroundStyle(Color.privioBright)
                    .padding(20)
                    .background(Circle().fill(.white.opacity(0.08)))
                    .overlay(Circle().strokeBorder(Color.privioBright.opacity(0.35), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Authenticate with Touch ID")

            Button(action: onAuthenticate) {
                Text("Authenticate")
                    .font(.privioSystem(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(PrivioGradient.brand))
            }
            .buttonStyle(.plain)

            // „Use Password" jest zawsze dostępny jako escape hatch do hasła Maca
            // (systemowy prompt „Wprowadź hasło"). Wymusza deviceOwnerAuthentication.
            Button(action: onUsePassword) {
                Text("Use Mac Password")
                    .font(.privioSystem(size: 13, weight: .medium))
                    .foregroundStyle(Color.privioBright)
            }
            .buttonStyle(.plain)
        }
        .padding(30)
        .frame(width: 320)
        .background(PrivioGradient.authCard)
        .overlay(alignment: .topTrailing) {
            Button(action: onCancel) {
                FAIcon("xmark", size: 11)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(8)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .task {
            // Auto‑uruchom systemowy prompt Touch ID przy pojawieniu się okna.
            // Nasze okno tylko wyjaśnia powód; biometria pochodzi z systemu.
            if !didAutoStart {
                didAutoStart = true
                onAuthenticate()
            }
        }
    }
}

#if DEBUG
#Preview {
    LockedAuthView(
        app: PreviewData.sampleApps[0].app,
        allowPasswordFallback: true,
        onAuthenticate: {}, onUsePassword: {}, onCancel: {})
        .padding(40)
}
#endif
