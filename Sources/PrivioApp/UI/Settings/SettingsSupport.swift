import SwiftUI
import PrivioCore

/// Shared spacing grid for every main Privio section. Dense controls may use
/// smaller internal spacing, but page edges and section rhythm stay identical.
enum PrivioLayout {
    static let pagePadding: CGFloat = 24
    static let headerTop: CGFloat = 22
    static let headerBottom: CGFloat = 16
    static let sectionSpacing: CGFloat = 22
    static let cardPadding: CGFloat = 16
    static let cardSpacing: CGFloat = 12
    static let rowSpacing: CGFloat = 8
}

/// Wspólny szkielet ekranów ustawień (nagłówek + przewijana treść w kartach).
struct SettingsScreen<Content: View, HeaderAccessory: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var headerAccessory: () -> HeaderAccessory
    @ViewBuilder var content: () -> Content

    init(
        title: LocalizedStringKey,
        @ViewBuilder headerAccessory: @escaping () -> HeaderAccessory,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.headerAccessory = headerAccessory
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.privioSystem(size: 24, weight: .bold))
                    .foregroundStyle(Color.privioTextPrimary)
                Spacer()
                headerAccessory()
            }
            .padding(.horizontal, PrivioLayout.pagePadding)
            .padding(.top, PrivioLayout.headerTop)
            .padding(.bottom, PrivioLayout.headerBottom)

            Divider().overlay(Color.privioSeparator)

            ScrollView {
                VStack(alignment: .leading, spacing: PrivioLayout.sectionSpacing) {
                    content()
                }
                .padding(PrivioLayout.pagePadding)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }
}

extension SettingsScreen where HeaderAccessory == EmptyView {
    init(title: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, headerAccessory: { EmptyView() }, content: content)
    }
}

struct SettingsCard<Content: View>: View {
    let title: LocalizedStringKey?
    @ViewBuilder var content: () -> Content

    init(_ title: LocalizedStringKey? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.privioSystem(size: 12, weight: .semibold))
                    .foregroundStyle(Color.privioTextSecondary)
                    .textCase(.uppercase)
                    .padding(.bottom, 8)
            }
            VStack(spacing: PrivioLayout.cardSpacing) { content() }
                .padding(PrivioLayout.cardPadding)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.privioSurface)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.privioSeparator, lineWidth: 1))
                )
        }
    }
}

struct SettingsToggleRow: View {
    let label: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.privioSystem(size: 13.5))
                    .foregroundStyle(Color.privioTextPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.privioSystem(size: 11.5))
                        .foregroundStyle(Color.privioTextTertiary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden().toggleStyle(.switch).controlSize(.small).tint(.privioPrimary)
        }
    }
}
