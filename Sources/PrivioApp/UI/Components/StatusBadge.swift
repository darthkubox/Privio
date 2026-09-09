import SwiftUI
import PrivioCore

/// Etykieta stanu blokady. Stan komunikowany ikoną + tekstem, nie tylko kolorem
/// (sekcja 23 - dostępność).
struct StatusBadge: View {
    let status: LockStatus
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            FAIcon(status.symbolName, size: compact ? 10 : 11)
            Text(LocalizedStringKey(status.label))
                .font(.privioSystem(size: compact ? 11.5 : 12.5, weight: .medium))
        }
        .foregroundStyle(tint)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(status.label)
    }

    private var tint: Color {
        switch status {
        case .unlocked:       return .privioUnlocked
        case .locked:         return .privioLockedTint
        case .authenticating: return .privioPrimary
        case .unprotected:    return .privioTextTertiary
        }
    }
}
