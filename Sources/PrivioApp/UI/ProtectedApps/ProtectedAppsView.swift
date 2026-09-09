import SwiftUI
import AppKit
import PrivioCore

struct ProtectedAppsView: View {
    @Environment(AppModel.self) private var model
    @State private var showingAddSheet = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            // Nagłówek
            HStack(spacing: 14) {
                Text("Protected Apps")
                    .font(.privioSystem(size: 24, weight: .bold))
                    .foregroundStyle(Color.privioTextPrimary)
                Spacer()
                HStack(spacing: 7) {
                    Text("App protection")
                        .font(.privioSystem(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.privioTextSecondary)
                    Toggle("", isOn: Binding(
                        get: { model.appBlockingEnabled },
                        set: { model.setAppBlockingEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(.privioPrimary)
                }
                Button { showingAddSheet = true } label: {
                    HStack(spacing: 6) {
                        FAIcon("plus")
                        Text("Add Application")
                    }
                    .font(.privioSystem(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(PrivioGradient.brand))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, PrivioLayout.pagePadding)
            .padding(.top, PrivioLayout.headerTop)
            .padding(.bottom, PrivioLayout.headerBottom)

            Divider().overlay(Color.privioSeparator)

            // Treść: lista + detal
            HStack(spacing: 0) {
                listColumn
                    .frame(minWidth: 320, maxWidth: 420)
                Divider().overlay(Color.privioSeparator)
                detailColumn
                    .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddApplicationSheet()
                .environment(model)
        }
    }

    // MARK: - Lista

    private var listColumn: some View {
        @Bindable var model = model
        return VStack(spacing: 12) {
            SearchField(text: $model.searchText, placeholder: "Search applications…")
                .padding(.horizontal, PrivioLayout.pagePadding)
                .padding(.top, PrivioLayout.pagePadding)

            if model.filteredApps.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: PrivioLayout.rowSpacing) {
                        ForEach(model.filteredApps) { snapshot in
                            ProtectedAppRow(
                                snapshot: snapshot,
                                status: model.effectiveStatus(snapshot),
                                isSelected: model.selectedAppID == snapshot.id,
                                onSelect: { model.selectedAppID = snapshot.id },
                                onToggleProtection: { model.setProtectionEnabled($0, for: snapshot.app) }
                            )
                        }
                    }
                    .padding(.horizontal, PrivioLayout.pagePadding)
                    .padding(.bottom, PrivioLayout.pagePadding)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            FAIcon("lock.app.dashed", size: 40)
                .foregroundStyle(Color.privioTextTertiary)
            Text(model.searchText.isEmpty ? "No protected apps yet" : "No matches")
                .font(.privioSystem(size: 14, weight: .medium))
                .foregroundStyle(Color.privioTextSecondary)
            if model.searchText.isEmpty {
                Text("Add an application to protect it with Touch ID or password.")
                    .font(.privioSystem(size: 12))
                    .foregroundStyle(Color.privioTextTertiary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    // MARK: - Detal

    @ViewBuilder
    private var detailColumn: some View {
        if let snapshot = model.selectedSnapshot {
            AppDetailPanel(snapshot: snapshot)
        } else {
            VStack(spacing: 8) {
                FAIcon("hand.point.up.left", size: 32)
                    .foregroundStyle(Color.privioTextTertiary)
                Text("Select an app to configure it")
                    .font(.privioSystem(size: 14))
                    .foregroundStyle(Color.privioTextSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

}

/// Pole wyszukiwania w stylu Privio.
struct SearchField: View {
    @Binding var text: String
    var placeholder: LocalizedStringKey

    var body: some View {
        HStack(spacing: 8) {
            FAIcon("magnifyingglass", size: 13)
                .foregroundStyle(Color.privioTextTertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.privioSystem(size: 13))
            if !text.isEmpty {
                Button { text = "" } label: {
                    FAIcon("xmark.circle.fill")
                        .foregroundStyle(Color.privioTextTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.privioSurface)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.privioSeparator, lineWidth: 1))
        )
    }
}
