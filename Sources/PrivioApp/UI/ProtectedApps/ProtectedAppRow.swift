import SwiftUI
import PrivioCore

/// Wiersz listy chronionych aplikacji (mockup): ikona, nazwa, bundleID, status,
/// przełącznik ochrony i chevron do detalu.
struct ProtectedAppRow: View {
    let snapshot: ProtectedAppSnapshot
    let status: LockStatus
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleProtection: (Bool) -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                AppIconView(app: snapshot.app, size: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.app.displayName)
                        .font(.privioSystem(size: 14, weight: .semibold))
                        .foregroundStyle(Color.privioTextPrimary)
                    Text(snapshot.app.bundleIdentifier)
                        .font(.privioSystem(size: 11.5))
                        .foregroundStyle(Color.privioTextTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                StatusBadge(status: status, compact: true)

                Toggle("", isOn: Binding(
                    get: { snapshot.app.protectionEnabled },
                    set: { onToggleProtection($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(.privioPrimary)
                .accessibilityLabel("Protect \(snapshot.app.displayName)")

                FAIcon("chevron.right", size: 11)
                    .foregroundStyle(Color.privioTextTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(rowBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? Color.privioPrimary.opacity(0.5) : Color.privioSeparator,
                                          lineWidth: isSelected ? 1.5 : 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var rowBackground: Color {
        if isSelected { return .privioSurfaceSelected }
        return hovering ? .privioSurfaceSelected.opacity(0.5) : .privioSurface
    }
}
