import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PrivioCore

/// „Add Application" (sekcja 6): przeglądaj/wyszukaj zainstalowane apki, albo
/// wybierz ręcznie przez NSOpenPanel. Privio nie może chronić samej siebie
/// (katalog wyklucza własny bundleID; ręczny wybór też jest sprawdzany).
struct AddApplicationSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var installed: [InstalledApp] = []
    @State private var loading = true
    @State private var search = ""

    private var results: [InstalledApp] {
        let already = model.protectedBundleIDs
        let base = installed.filter { !already.contains($0.bundleIdentifier) }
        guard !search.isEmpty else { return base }
        let q = search.lowercased()
        return base.filter {
            $0.displayName.lowercased().contains(q) || $0.bundleIdentifier.lowercased().contains(q)
        }
    }

    var body: some View {
        PrivioModal(title: "Add Application", width: 460, height: 560) {
            VStack(spacing: 0) {
                SearchField(text: $search, placeholder: "Search applications…")
                    .padding(.bottom, 14)

                if loading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(results) { app in
                                InstalledAppRow(app: app) { add(app) }
                            }
                        }
                        .padding(.bottom, 4)
                    }
                }
            }
        } footer: {
            Button("Choose Manually…", action: chooseManually)
                .privioSecondaryButton()
            Spacer()
            Button("Done") { dismiss() }
                .privioPrimaryButton()
                .keyboardShortcut(.defaultAction)
        }
        .task {
            installed = await model.scanInstalledApps()
            loading = false
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            FAIcon("magnifyingglass", size: 32)
                .foregroundStyle(Color.privioTextTertiary)
            Text(LocalizedStringKey(search.isEmpty ? "All installed apps are already protected" : "No matches"))
                .font(.privioSystem(size: 13))
                .foregroundStyle(Color.privioTextSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func add(_ installedApp: InstalledApp) {
        model.addApp(model.makeProtectedApp(from: installedApp))
        // Zostań w arkuszu, by dodać więcej - lista sama odfiltruje dodaną apkę.
    }

    private func chooseManually() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = NSLocalizedString("Protect", comment: "Confirm manually selected protected app")
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return }
        if bundleID == Bundle.main.bundleIdentifier {
            presentError("Privio can’t protect itself."); return
        }
        if model.protectedBundleIDs.contains(bundleID) {
            presentError("That app is already protected."); return
        }
        let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        model.addApp(model.makeProtectedApp(
            from: InstalledApp(bundleIdentifier: bundleID, displayName: name, url: url)))
        dismiss()
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Couldn’t add application", comment: "Add protected app error title")
        alert.informativeText = NSLocalizedString(message, comment: "Add protected app error message")
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private struct InstalledAppRow: View {
    let app: InstalledApp
    let onAdd: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(installed: app, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.privioSystem(size: 13.5, weight: .medium))
                    .foregroundStyle(Color.privioTextPrimary)
                Text(app.bundleIdentifier)
                    .font(.privioSystem(size: 11))
                    .foregroundStyle(Color.privioTextTertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button(action: onAdd) {
                FAIcon("plus.circle.fill", size: 18)
                    .foregroundStyle(Color.privioPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Protect \(app.displayName)")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(hovering ? Color.privioSurfaceSelected : Color.privioSurface))
        .onHover { hovering = $0 }
    }
}
