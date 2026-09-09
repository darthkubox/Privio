import AppKit
import PrivioCore
import SwiftUI
import UniformTypeIdentifiers

struct VaultView: View {
    @Environment(VaultController.self) private var vault
    @State private var tab: VaultTab = .files
    @State private var showRecoveryUnlock = false
    @State private var recoveryInput = ""
    @State private var launcherLocation: URL?

    var body: some View {
        SettingsScreen(title: "Private Vault", headerAccessory: {
            HStack(spacing: 7) {
                if vault.status == .notCreated {
                    Button { Task { _ = await vault.createVault() } } label: {
                        HStack(spacing: 6) {
                            FAIcon("plus")
                            Text("Create Private Vault")
                        }
                        .font(.privioSystem(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(PrivioGradient.brand))
                    }
                    .buttonStyle(.plain)
                    .disabled(!vault.isEnabled)
                    .opacity(vault.isEnabled ? 1 : 0.45)
                    .padding(.trailing, 7)
                }
                Text("Private Vault")
                    .font(.privioSystem(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.privioTextSecondary)
                Toggle("", isOn: Binding(
                    get: { vault.isEnabled },
                    set: { enabled in Task { await vault.setEnabled(enabled) } }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(.privioPrimary)
                .disabled(isWorking)
            }
        }) {
            statusCard

            if vault.isEnabled {
                switch vault.status {
                case .notCreated:
                    setupCard
                case .locked:
                    EmptyView()
                case .working(let message):
                    workingCard(message)
                case .unlocked:
                    unlockedContent
                }
            }
        }
        .task { await vault.start() }
        .sheet(isPresented: recoveryKeyPresented) {
            RecoveryKeySheet(key: vault.recoveryKeyToPresent ?? "") {
                vault.dismissRecoveryKey()
            }
        }
        .sheet(isPresented: $showRecoveryUnlock) {
            RecoveryUnlockSheet(key: $recoveryInput, onCancel: {
                recoveryInput = ""
                showRecoveryUnlock = false
            }, onUnlock: {
                let key = recoveryInput
                Task {
                    if await vault.unlock(recoveryKey: key) {
                        recoveryInput = ""
                        showRecoveryUnlock = false
                    }
                }
            })
        }
        .alert("Private Vault", isPresented: errorPresented) {
            Button("OK") { vault.clearError() }
        } message: {
            Text(vault.errorMessage ?? "")
        }
    }

    private var isWorking: Bool {
        if case .working = vault.status { return true }
        return false
    }

    private var statusCard: some View {
        SettingsCard {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(vault.isUnlocked ? Color.privioUnlocked.opacity(0.13) : Color.privioPrimary.opacity(0.13))
                        .frame(width: 52, height: 52)
                    VaultStatusSymbol(state: vault.isUnlocked ? .unlocked : vault.isConfigured ? .locked : .neutral)
                        .frame(width: 29, height: 29)
                        .foregroundStyle(vault.isUnlocked ? Color.privioUnlocked : Color.privioPrimary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(.privioSystem(size: 16, weight: .semibold))
                        .foregroundStyle(Color.privioTextPrimary)
                    Text(statusDescription)
                        .font(.privioSystem(size: 11.5))
                        .foregroundStyle(Color.privioTextTertiary)
                }
                Spacer()
                if vault.isUnlocked {
                    Button("Open in Finder") { vault.openFinder() }
                        .buttonStyle(.borderedProminent).tint(.privioPrimary)
                    Button("Lock") { Task { _ = await vault.lock() } }
                        .buttonStyle(.bordered)
                } else if vault.isEnabled && vault.status == .locked {
                    Button("Unlock Vault") { Task { _ = await vault.unlock() } }
                        .buttonStyle(.borderedProminent).tint(.privioPrimary)
                    Button("Use Recovery Key…") { showRecoveryUnlock = true }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private var setupCard: some View {
        SettingsCard("Set up") {
            Text("Create a private APFS vault encrypted with AES-256. Its key is protected by Touch ID or your Mac password and never leaves this Mac.")
                .font(.privioSystem(size: 13)).foregroundStyle(Color.privioTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                FAIcon("exclamationmark.triangle.fill")
                    .foregroundStyle(Color.orange)
                Text("You will receive a recovery key once. Keep it outside this Mac - without it, losing Keychain access makes the vault unrecoverable.")
                    .font(.privioSystem(size: 11.5)).foregroundStyle(Color.privioTextTertiary)
            }
        }
    }

    private func workingCard(_ message: String) -> some View {
        SettingsCard {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text(message).font(.privioSystem(size: 13.5)).foregroundStyle(Color.privioTextSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 70)
        }
    }

    @ViewBuilder
    private var unlockedContent: some View {
        Picker("", selection: $tab) {
            ForEach(VaultTab.allCases) { item in
                // Segmentowany przełącznik = same teksty (Pliki / Notatki / Ustawienia).
                // NSSegmentedControl nie renderuje glifu FA (Text z własnym krojem), więc
                // ikona pokazywałaby się jako brakujący znak - używamy czystego tekstu.
                Text(item.title).tag(item)
            }
        }
        .labelsHidden().pickerStyle(.segmented)

        switch tab {
        case .files: VaultFilesCard()
        case .notes: VaultNotesCard()
        case .settings: VaultSettingsCard(launcherLocation: $launcherLocation)
        }
    }

    private var statusDescription: LocalizedStringKey {
        if !vault.isEnabled {
            return "The vault is disabled. Its encrypted data and keys remain safely stored on this Mac."
        }
        if vault.isUnlocked {
            return "Files are readable while the vault is mounted. Lock it when you finish."
        }
        if vault.isConfigured {
            return "The encrypted image is not mounted and its contents cannot be read."
        }
        return "Encrypted files and private notes in one protected place."
    }

    private var statusTitle: LocalizedStringKey {
        if !vault.isEnabled { return "Vault disabled" }
        return vault.isUnlocked ? "Vault unlocked" : vault.isConfigured ? "Vault locked" : "Encrypted vault"
    }

    private var recoveryKeyPresented: Binding<Bool> {
        Binding(get: { vault.recoveryKeyToPresent != nil }, set: { if !$0 { vault.dismissRecoveryKey() } })
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { vault.errorMessage != nil }, set: { if !$0 { vault.clearError() } })
    }
}

private enum VaultTab: String, CaseIterable, Identifiable {
    case files, notes, settings
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self { case .files: "Files"; case .notes: "Notes"; case .settings: "Settings" }
    }
    var symbol: String {
        switch self { case .files: "doc.fill"; case .notes: "note.text"; case .settings: "gearshape" }
    }
}

/// Zbiera adresy URL z asynchronicznych providerów upuszczonych plików (kolejność
/// dostarczenia jest nieokreślona - dla importu nie ma to znaczenia).
private final class DroppedURLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    func append(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }
    func all() -> [URL] { lock.lock(); defer { lock.unlock() }; return urls }
}

private struct VaultFilesCard: View {
    @Environment(VaultController.self) private var vault
    @State private var isDropTargeted = false

    var body: some View {
        SettingsCard("Encrypted files") {
            HStack {
                Button { chooseFiles() } label: { Label("Add Files…", fa: "plus") }
                    .buttonStyle(.borderedProminent).tint(.privioPrimary)
                Button { vault.refreshContents() } label: { Label("Refresh", fa: "arrow.clockwise") }
                    .buttonStyle(.bordered)
                Spacer()
                Text("\(vault.files.count) items")
                    .font(.privioSystem(size: 11.5)).foregroundStyle(Color.privioTextTertiary)
            }

            Divider().overlay(Color.privioSeparator)
            if vault.files.isEmpty {
                VStack(spacing: 10) {
                    FAIcon("arrow.down.doc.fill", size: 30).foregroundStyle(Color.privioTextTertiary)
                    Text("No files yet").font(.privioSystem(size: 13.5, weight: .medium))
                    Text("Drag files here, add them, or open the mounted vault in Finder.")
                        .font(.privioSystem(size: 11.5)).foregroundStyle(Color.privioTextTertiary)
                }.frame(maxWidth: .infinity, minHeight: 150)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(vault.files) { item in
                        HStack(spacing: 11) {
                            FAIcon(item.isDirectory ? "folder.fill" : "doc.fill")
                                .foregroundStyle(item.isDirectory ? Color.privioPrimary : Color.privioTextSecondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.privioSystem(size: 13.5)).foregroundStyle(Color.privioTextPrimary)
                                Text(fileSubtitle(item))
                                    .font(.privioSystem(size: 10.5)).foregroundStyle(Color.privioTextTertiary)
                            }
                            Spacer()
                            Button("Show") { vault.reveal(item) }.buttonStyle(.borderless)
                            Button("Open") { vault.open(item) }.buttonStyle(.bordered).controlSize(.small)
                        }
                        .padding(.vertical, 9)
                        if item.id != vault.files.last?.id { Divider().overlay(Color.privioSeparator) }
                    }
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted.animation(.easeInOut(duration: 0.12))) { handleDrop($0) }
        .overlay { dropHighlight }
    }

    @ViewBuilder private var dropHighlight: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.privioPrimary.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.privioPrimary, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                )
                .overlay(
                    Label("Drop to add to the vault", fa: "arrow.down.doc.fill")
                        .font(.privioSystem(size: 13, weight: .semibold))
                        .foregroundStyle(Color.privioPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                )
                .allowsHitTesting(false)
        }
    }

    /// Odbiór plików upuszczonych z Findera. `importFiles` sam odrzuca dowiązania,
    /// sam obraz sejfu i ścieżki z jego wnętrza ([[vault-import-policy]]).
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let identifier = UTType.fileURL.identifier
        let relevant = providers.filter { $0.hasItemConformingToTypeIdentifier(identifier) }
        guard !relevant.isEmpty else { return false }
        let collector = DroppedURLCollector()
        let group = DispatchGroup()
        for provider in relevant {
            group.enter()
            provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    collector.append(url)
                } else if let url = item as? URL {
                    collector.append(url)
                }
            }
        }
        group.notify(queue: .main) {
            let urls = collector.all()
            guard !urls.isEmpty else { return }
            Task { @MainActor in vault.importFiles(urls) }
        }
        return true
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK else { return }
        vault.importFiles(panel.urls)
    }

    private func fileSubtitle(_ item: VaultFileItem) -> String {
        if item.isDirectory { return NSLocalizedString("Folder", comment: "Vault file kind") }
        guard let size = item.size else { return NSLocalizedString("File", comment: "Vault file kind") }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

private struct VaultNotesCard: View {
    @Environment(VaultController.self) private var vault

    var body: some View {
        SettingsCard("Encrypted notes") {
            HStack {
                Button { vault.addNote() } label: { Label("New Note", fa: "square.and.pencil") }
                    .buttonStyle(.borderedProminent).tint(.privioPrimary)
                Spacer()
                Text("Stored only inside the encrypted vault")
                    .font(.privioSystem(size: 11.5)).foregroundStyle(Color.privioTextTertiary)
            }
            Divider().overlay(Color.privioSeparator)
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 3) {
                    if vault.notes.isEmpty {
                        Text("No notes").font(.privioSystem(size: 12)).foregroundStyle(Color.privioTextTertiary)
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        ForEach(vault.notes) { note in
                            Button {
                                vault.selectedNoteID = note.id
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(note.title).lineLimit(1).font(.privioSystem(size: 12.5, weight: .medium))
                                    Text(note.updatedAt, style: .date).font(.privioSystem(size: 10)).opacity(0.7)
                                }
                                .foregroundStyle(vault.selectedNoteID == note.id ? Color.white : Color.privioTextSecondary)
                                .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 7).fill(
                                    vault.selectedNoteID == note.id ? Color.privioPrimary : Color.clear))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .frame(width: 190)
                Divider().overlay(Color.privioSeparator)
                if let note = vault.notes.first(where: { $0.id == vault.selectedNoteID }) {
                    VaultNoteEditor(note: note)
                        .id(note.id)
                } else {
                    Text("Select a note or create a new one.")
                        .font(.privioSystem(size: 12.5)).foregroundStyle(Color.privioTextTertiary)
                        .frame(maxWidth: .infinity, minHeight: 220)
                }
            }
        }
    }
}

private struct VaultNoteEditor: View {
    @Environment(VaultController.self) private var vault
    let note: VaultNote
    @State private var title: String
    @State private var bodyText: String

    init(note: VaultNote) {
        self.note = note
        _title = State(initialValue: note.title)
        _bodyText = State(initialValue: note.body)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Title", text: $title)
                    .textFieldStyle(.plain).font(.privioSystem(size: 16, weight: .semibold))
                Button(role: .destructive) { vault.deleteNote(id: note.id) } label: {
                    FAIcon("trash")
                        .foregroundStyle(Color.privioDanger)
                }
                .buttonStyle(.borderless)
            }
            Divider().overlay(Color.privioSeparator)
            TextEditor(text: $bodyText)
                .font(.privioSystem(size: 13)).scrollContentBackground(.hidden)
                .frame(minHeight: 220)
        }
        .onChange(of: title) { _, _ in save() }
        .onChange(of: bodyText) { _, _ in save() }
    }

    private func save() { vault.updateNote(id: note.id, title: title, body: bodyText) }

}

private struct VaultSettingsCard: View {
    @Environment(VaultController.self) private var vault
    @Binding var launcherLocation: URL?
    @State private var showDeleteConfirmation = false

    var body: some View {
        @Bindable var vault = vault
        SettingsCard("Security") {
            SettingsToggleRow(
                label: "Lock when the screen is locked",
                subtitle: "Unmounts the encrypted volume immediately.",
                isOn: $vault.preferences.lockOnScreenLock
            )
            Divider().overlay(Color.privioSeparator)
            SettingsToggleRow(
                label: "Lock when Mac sleeps",
                subtitle: "Unmounts the encrypted volume before sleep.",
                isOn: $vault.preferences.lockOnSleep
            )
            Divider().overlay(Color.privioSeparator)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Time after the last action in Privio").font(.privioSystem(size: 13.5)).foregroundStyle(Color.privioTextPrimary)
                    Text("Open files can prevent safe locking; Privio never forces an unsafe eject.")
                        .font(.privioSystem(size: 11.5)).foregroundStyle(Color.privioTextTertiary)
                }
                Spacer()
                Picker("", selection: $vault.preferences.autoLockMinutes) {
                    Text("Never").tag(0)
                    Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                }.labelsHidden().pickerStyle(.menu).fixedSize()
            }
        }

        SettingsCard("Recovery") {
            Text("Your recovery key can open the vault if the protected Keychain entry is lost. Anyone who has this key can decrypt the vault.")
                .font(.privioSystem(size: 12)).foregroundStyle(Color.privioTextTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Show Recovery Key…") { Task { await vault.showRecoveryKey() } }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        SettingsCard("Finder & Dock shortcut") {
            Text("Create a movable shortcut with a macOS folder icon and the Privio mark. It can be kept anywhere or dragged to the right side of the Dock. Opening it always authenticates before mounting the vault.")
                .font(.privioSystem(size: 12)).foregroundStyle(Color.privioTextTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Button("Add Vault Shortcut…") {
                    do { launcherLocation = try VaultLauncherService.install() }
                    catch { vault.report(error) }
                }.buttonStyle(.borderedProminent).tint(.privioPrimary)
                if let launcherLocation {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([launcherLocation])
                    }.buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        SettingsCard("Delete Vault") {
            Text("Permanently delete the encrypted vault and everything stored inside it. This action cannot be undone.")
                .font(.privioSystem(size: 12))
                .foregroundStyle(Color.privioTextTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack(spacing: 6) {
                    FAIcon("trash")
                    Text("Delete Vault…")
                }
                .font(.privioSystem(size: 13, weight: .medium))
                .foregroundStyle(Color.privioDanger)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("Delete Private Vault?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Forever", role: .destructive) {
                Task {
                    await Task.yield()
                    try? await Task.sleep(for: .milliseconds(150))
                    _ = await vault.deleteVault()
                }
            }
        } message: {
            Text("All files and private notes in this vault will be permanently lost. You will need to confirm with Touch ID or your Mac password.")
        }
    }
}

private struct RecoveryKeySheet: View {
    let key: String
    let onDone: () -> Void

    /// Klucz jako równy blok: 4 grupy w wierszu, monospace, wyśrodkowany - inaczej
    /// długi ciąg zawija się w losowym miejscu i „rozjeżdża".
    private var formattedKey: String {
        let groups = key.split(whereSeparator: { $0 == "-" || $0 == "-" }).map(String.init)
        return stride(from: 0, to: groups.count, by: 4)
            .map { groups[$0..<min($0 + 4, groups.count)].joined(separator: " - ") }
            .joined(separator: "\n")
    }

    var body: some View {
        PrivioModal(title: "Save your recovery key",
                    subtitle: "This key is the only fallback if Keychain access is lost. Store it in a password manager or print it. Never keep the only copy inside this vault.",
                    width: 560) {
            Text(formattedKey)
                .font(.privioSystem(size: 14, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .textSelection(.enabled)
                .padding(16).frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.privioSurface))
        } footer: {
            Button("Copy") { copyTemporarily() }.privioSecondaryButton()
            Spacer()
            Button("I Saved It") { onDone() }.privioPrimaryButton()
        }
        .interactiveDismissDisabled()
    }

    private func copyTemporarily() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(key, forType: .string)
        let changeCount = pasteboard.changeCount
        Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard pasteboard.changeCount == changeCount,
                  pasteboard.string(forType: .string) == key else { return }
            pasteboard.clearContents()
        }
    }
}

private struct RecoveryUnlockSheet: View {
    @Binding var key: String
    let onCancel: () -> Void
    let onUnlock: () -> Void

    var body: some View {
        PrivioModal(title: "Use Recovery Key",
                    subtitle: "Enter the 64-character recovery key created with this vault.",
                    width: 520) {
            PrivioModalField {
                SecureField("Recovery key", text: $key)
                    .textFieldStyle(.plain)
                    .font(.privioSystem(size: 14, design: .monospaced))
            }
        } footer: {
            Button("Cancel", action: onCancel).privioSecondaryButton().keyboardShortcut(.cancelAction)
            Spacer()
            Button("Unlock", action: onUnlock).privioPrimaryButton()
                .keyboardShortcut(.defaultAction)
                .disabled(!VaultRecoveryKey.isValid(key))
        }
    }
}
