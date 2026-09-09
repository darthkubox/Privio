import AppKit
import Foundation
import Observation
import PrivioCore

@MainActor
@Observable
final class VaultController {
    private(set) var status: VaultStatus
    private(set) var files: [VaultFileItem] = []
    private(set) var notes: [VaultNote] = []
    private(set) var errorMessage: String?
    private(set) var recoveryKeyToPresent: String?
    private(set) var isEnabled: Bool
    var selectedNoteID: UUID?
    var preferences: VaultPreferences { didSet { savePreferences(); scheduleAutoLock() } }

    @ObservationIgnored private let disk: VaultDiskImageService
    @ObservationIgnored private let keys = VaultKeyStore()
    @ObservationIgnored private let authenticator = LocalAuthenticator()
    @ObservationIgnored private let events = WorkspaceSystemEventMonitor()
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var autoLockTask: Task<Void, Never>?
    @ObservationIgnored private var noteSaveTask: Task<Void, Never>?
    @ObservationIgnored private var notesDirty = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private let isSnapshot: Bool

    private static let lockOnScreenKey = "privio.vault.lockOnScreenLock"
    private static let lockOnSleepKey = "privio.vault.lockOnSleep"
    private static let autoLockKey = "privio.vault.autoLockMinutes"
    private static let enabledKey = "privio.vault.enabled"

    init(isSnapshot: Bool = false, disk: VaultDiskImageService = VaultDiskImageService()) {
        self.isSnapshot = isSnapshot
        self.disk = disk
        let defaults = UserDefaults.standard
        self.isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        self.preferences = VaultPreferences(
            lockOnScreenLock: defaults.object(forKey: Self.lockOnScreenKey) as? Bool ?? true,
            lockOnSleep: defaults.object(forKey: Self.lockOnSleepKey) as? Bool ?? true,
            autoLockMinutes: defaults.object(forKey: Self.autoLockKey) as? Int ?? 0
        )
        self.status = isSnapshot || FileManager.default.fileExists(atPath: VaultPaths.imageURL.path)
            ? .locked : .notCreated
    }

    var isConfigured: Bool { status != .notCreated }
    var isUnlocked: Bool { status.isUnlocked }
    var mountURL: URL? {
        guard case .unlocked(let mount) = status else { return nil }
        return mount.url
    }

    /// Wyłączenie modułu nigdy nie usuwa obrazu ani kluczy. Najpierw musi się
    /// udać bezpieczne odmontowanie; w przeciwnym razie stan pozostaje włączony.
    func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled else { return }
        if enabled {
            isEnabled = true
            UserDefaults.standard.set(true, forKey: Self.enabledKey)
            return
        }
        guard await lock() else { return }
        isEnabled = false
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        autoLockTask?.cancel()
    }

    func start() async {
        guard !started, !isSnapshot else { return }
        started = true

        // Po niekontrolowanym zakończeniu poprzedniej sesji nie ufamy samemu
        // faktowi montowania. Sejf zostaje natychmiast odłączony i wraca do LOCKED.
        if let existing = try? await disk.currentMount() {
            do {
                try await disk.detach(existing)
            } catch {
                status = .unlocked(existing)
                errorMessage = NSLocalizedString(
                    "The vault remained mounted after the previous session. Close files stored in it and lock it now.",
                    comment: "Vault startup safety error"
                )
                refreshContents()
                return
            }
        }
        status = await disk.exists() ? .locked : .notCreated

        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.events.start() {
                switch event {
                case .screenLocked where self.preferences.lockOnScreenLock,
                     .sessionResigned where self.preferences.lockOnScreenLock,
                     .willSleep where self.preferences.lockOnSleep:
                    _ = await self.lock()
                default:
                    break
                }
            }
        }
    }

    /// Tworzy nowy obraz i zwraca jednorazowo klucz odzyskiwania do zapisania.
    @discardableResult
    func createVault(capacityGB: Int = 20) async -> Bool {
        guard isEnabled, status == .notCreated else { return false }
        errorMessage = nil
        let auth = await authenticator.authenticate(
            reason: localized("create the encrypted Privio Vault", pl: "utworzyć zaszyfrowany Sejf Privio"),
            policy: .biometricsOrPassword
        )
        guard auth == .success else { return false }

        status = .working(NSLocalizedString("Creating encrypted vault…", comment: "Vault progress"))
        let password = VaultRecoveryKey.generate()
        do {
            try await keys.store(password)
            do {
                try await disk.create(password: password, capacityGB: capacityGB)
            } catch {
                keys.remove()
                throw error
            }
            recoveryKeyToPresent = Self.displayRecoveryKey(password)
            let mount = try await disk.attach(password: password)
            try prepareMountedVolume(mount.url)
            status = .unlocked(mount)
            refreshContents()
            scheduleAutoLock()
            return true
        } catch {
            errorMessage = error.localizedDescription
            if let mounted = try? await disk.currentMount() {
                status = .unlocked(mounted)
                refreshContents()
            } else {
                status = FileManager.default.fileExists(atPath: VaultPaths.imageURL.path) ? .locked : .notCreated
            }
            return false
        }
    }

    @discardableResult
    func unlock(openInFinder: Bool = false) async -> Bool {
        guard isEnabled else { return false }
        if isUnlocked {
            if openInFinder { openFinder() }
            return true
        }
        guard status == .locked else { return false }
        errorMessage = nil
        status = .working(NSLocalizedString("Unlocking…", comment: "Vault progress"))
        do {
            let password = try await keys.read(
                reason: localized("Open the encrypted Privio Vault", pl: "Otwórz zaszyfrowany Sejf Privio")
            )
            return try await finishUnlock(password: password, openInFinder: openInFinder)
        } catch {
            errorMessage = error.localizedDescription
            if let mounted = try? await disk.currentMount() {
                status = .unlocked(mounted)
                refreshContents()
            } else {
                status = .locked
            }
            return false
        }
    }

    /// Awaryjne otwarcie po utracie wpisu Pęku kluczy. Po sukcesie klucz jest
    /// ponownie chroniony przez obecność użytkownika.
    @discardableResult
    func unlock(recoveryKey: String, openInFinder: Bool = false) async -> Bool {
        guard isEnabled, status == .locked else { return false }
        let normalized = Self.normalizeRecoveryKey(recoveryKey)
        guard normalized.count == VaultRecoveryKey.normalizedLength else {
            errorMessage = NSLocalizedString("The recovery key is invalid.", comment: "Vault recovery error")
            return false
        }
        let auth = await authenticator.authenticate(
            reason: localized("use the Privio Vault recovery key", pl: "użyć klucza odzyskiwania Sejfu Privio"),
            policy: .biometricsOrPassword
        )
        guard auth == .success else { return false }
        status = .working(NSLocalizedString("Recovering vault…", comment: "Vault progress"))
        do {
            let success = try await finishUnlock(password: normalized, openInFinder: openInFinder)
            if success { try await keys.store(normalized) }
            return success
        } catch {
            errorMessage = error.localizedDescription
            if let mounted = try? await disk.currentMount() {
                status = .unlocked(mounted)
                refreshContents()
            } else {
                status = .locked
            }
            return false
        }
    }

    @discardableResult
    func lock() async -> Bool {
        guard case .unlocked(let mount) = status else { return true }
        errorMessage = nil
        noteSaveTask?.cancel()
        if notesDirty && !saveNotes() { return false }
        status = .working(NSLocalizedString("Locking…", comment: "Vault progress"))
        autoLockTask?.cancel()
        do {
            try await disk.detach(mount)
            files = []
            notes = []
            selectedNoteID = nil
            status = .locked
            return true
        } catch {
            // Nigdy nie pokazujemy fałszywego LOCKED, jeśli odmontowanie nie wyszło.
            status = .unlocked(mount)
            errorMessage = NSLocalizedString(
                "The vault is still open because one of its files is in use. Close the file and try again.",
                comment: "Vault detach failure"
            )
            return false
        }
    }

    /// Irreversibly removes both the encrypted image and its Keychain secret.
    /// UI confirmation happens first; this method always performs a fresh
    /// device-owner authentication immediately before the destructive action.
    @discardableResult
    func deleteVault() async -> Bool {
        guard isConfigured else { return false }
        if case .working = status { return false }
        errorMessage = nil

        let auth = await authenticator.authenticate(
            reason: localized("permanently delete the Privio Vault and all its data", pl: "trwale usunąć Sejf Privio i wszystkie jego dane"),
            policy: .biometricsOrPassword
        )
        guard auth == .success else { return false }
        guard await lock() else { return false }

        status = .working(NSLocalizedString("Deleting vault…", comment: "Vault deletion progress"))
        do {
            try await disk.delete()
            keys.remove()
            autoLockTask?.cancel()
            noteSaveTask?.cancel()
            files = []
            notes = []
            selectedNoteID = nil
            notesDirty = false
            recoveryKeyToPresent = nil
            status = .notCreated
            return true
        } catch {
            errorMessage = error.localizedDescription
            if let mounted = try? await disk.currentMount() {
                status = .unlocked(mounted)
                refreshContents()
            } else {
                status = await disk.exists() ? .locked : .notCreated
            }
            return false
        }
    }

    /// Wywoływane przez delegata aplikacji. Zakończenie jest anulowane, gdy
    /// bezpieczne odmontowanie nie jest możliwe.
    func prepareForTermination() async -> Bool {
        if case .working = status {
            errorMessage = NSLocalizedString(
                "Wait for the current vault operation to finish before quitting Privio.",
                comment: "Vault termination safety error"
            )
            return false
        }
        return await lock()
    }

    func openFinder() {
        guard let mountURL else { return }
        NSWorkspace.shared.open(mountURL)
        scheduleAutoLock()
    }

    func refreshContents() {
        guard let mountURL else { return }
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: mountURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []
        files = urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return VaultFileItem(
                url: url,
                name: url.lastPathComponent,
                isDirectory: values?.isDirectory ?? false,
                size: values?.fileSize.map(Int64.init),
                modifiedAt: values?.contentModificationDate
            )
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        notes = loadNotes(from: mountURL)
        if selectedNoteID == nil { selectedNoteID = notes.first?.id }
        scheduleAutoLock()
    }

    func importFiles(_ urls: [URL]) {
        guard let mountURL else { return }
        let canonicalImage = VaultPaths.imageURL.resolvingSymlinksInPath().standardizedFileURL
        for source in urls {
            let canonicalSource = source.resolvingSymlinksInPath().standardizedFileURL
            let isSymlink = (try? source.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
            if VaultImportPolicy.rejection(
                canonicalSource: canonicalSource,
                canonicalImage: canonicalImage,
                isSymbolicLink: isSymlink
            ) != nil {
                errorMessage = NSLocalizedString(
                    "Aliases, symbolic links, and the vault image itself cannot be imported.",
                    comment: "Vault import safety error"
                )
                break
            }
            let name = VaultImportPolicy.uniqueDestinationName(for: source) {
                FileManager.default.fileExists(atPath: mountURL.appendingPathComponent($0).path)
            }
            do {
                try FileManager.default.copyItem(at: source, to: mountURL.appendingPathComponent(name))
            } catch {
                errorMessage = error.localizedDescription
                break
            }
        }
        refreshContents()
    }

    func reveal(_ item: VaultFileItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
        scheduleAutoLock()
    }

    func open(_ item: VaultFileItem) {
        NSWorkspace.shared.open(item.url)
        scheduleAutoLock()
    }

    func addNote() {
        let note = VaultNote(title: NSLocalizedString("New note", comment: "Vault note title"))
        notes.insert(note, at: 0)
        selectedNoteID = note.id
        notesDirty = true
        scheduleNotesSave()
    }

    func updateNote(id: UUID, title: String, body: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].title = title.isEmpty ? NSLocalizedString("Untitled", comment: "Vault note title") : title
        notes[index].body = body
        notes[index].updatedAt = Date()
        notesDirty = true
        scheduleNotesSave()
        scheduleAutoLock()
    }

    func deleteNote(id: UUID) {
        notes.removeAll { $0.id == id }
        selectedNoteID = notes.first?.id
        notesDirty = true
        scheduleNotesSave()
    }

    func dismissRecoveryKey() { recoveryKeyToPresent = nil }
    func clearError() { errorMessage = nil }
    func report(_ error: Error) { errorMessage = error.localizedDescription }

    func showRecoveryKey() async {
        do {
            let key = try await keys.read(
                reason: localized("Show the Privio Vault recovery key", pl: "Pokaż klucz odzyskiwania Sejfu Privio")
            )
            recoveryKeyToPresent = Self.displayRecoveryKey(key)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finishUnlock(password: String, openInFinder: Bool) async throws -> Bool {
        let mount = try await disk.attach(password: password)
        try prepareMountedVolume(mount.url)
        status = .unlocked(mount)
        refreshContents()
        scheduleAutoLock()
        if openInFinder { openFinder() }
        return true
    }

    private func prepareMountedVolume(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        let noIndex = url.appendingPathComponent(".metadata_never_index")
        if !FileManager.default.fileExists(atPath: noIndex.path) {
            _ = FileManager.default.createFile(atPath: noIndex.path, contents: Data())
        }
        let metadata = url.appendingPathComponent(".privio", isDirectory: true)
        try FileManager.default.createDirectory(
            at: metadata,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private func notesURL(_ mountURL: URL) -> URL {
        mountURL.appendingPathComponent(".privio", isDirectory: true)
            .appendingPathComponent("notes.json")
    }

    private func loadNotes(from mountURL: URL) -> [VaultNote] {
        guard let data = try? Data(contentsOf: notesURL(mountURL)),
              let decoded = try? JSONDecoder().decode([VaultNote].self, from: data) else { return [] }
        return decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    private func saveNotes() -> Bool {
        guard let mountURL else { return false }
        do {
            let data = try JSONEncoder().encode(notes)
            let destination = notesURL(mountURL)
            try data.write(to: destination, options: [.atomic, .completeFileProtection])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            notesDirty = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func scheduleNotesSave() {
        noteSaveTask?.cancel()
        noteSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            _ = self?.saveNotes()
        }
    }

    private func savePreferences() {
        let defaults = UserDefaults.standard
        defaults.set(preferences.lockOnScreenLock, forKey: Self.lockOnScreenKey)
        defaults.set(preferences.lockOnSleep, forKey: Self.lockOnSleepKey)
        defaults.set(preferences.autoLockMinutes, forKey: Self.autoLockKey)
    }

    private func scheduleAutoLock() {
        autoLockTask?.cancel()
        guard isUnlocked, preferences.autoLockMinutes > 0 else { return }
        let delay = UInt64(preferences.autoLockMinutes) * 60 * 1_000_000_000
        autoLockTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            _ = await self?.lock()
        }
    }

    private func localized(_ english: String, pl polish: String) -> String {
        (Locale.preferredLanguages.first ?? "en").hasPrefix("pl") ? polish : english
    }

    static func normalizeRecoveryKey(_ value: String) -> String {
        VaultRecoveryKey.normalize(value)
    }

    static func displayRecoveryKey(_ value: String) -> String {
        VaultRecoveryKey.display(value)
    }
}
