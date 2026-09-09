import XCTest
@testable import PrivioCore

final class EnforcementTests: XCTestCase {

    private func tempStore() -> ConfigStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrivioTests-\(UUID().uuidString)", isDirectory: true)
        return ConfigStore(directory: dir)
    }

    private func sampleApp(_ name: String = "Signal",
                           bundle: String = "org.whispersystems.signal-desktop") -> ProtectedApp {
        ProtectedApp(bundleIdentifier: bundle, displayName: name,
                     applicationURL: URL(fileURLWithPath: "/Applications/\(name).app"))
    }

    // MARK: Persistencja

    func testConfigStoreRoundTrip() {
        let store = tempStore()
        var state = PersistedState()
        state.apps = [sampleApp()]
        state.configuration.defaultLockTimeout = 300
        store.save(state)

        let loaded = store.load()
        XCTAssertEqual(loaded.apps.count, 1)
        XCTAssertEqual(loaded.apps.first?.bundleIdentifier, "org.whispersystems.signal-desktop")
        XCTAssertEqual(loaded.configuration.defaultLockTimeout, 300)
    }

    /// Integralność (HMAC w Keychain) jest chwilowo wyłączona pod podpisem ad‑hoc -
    /// `integrityValid()` zawsze zwraca `true` i NIE dotyka pęku kluczy (żadnych monitów).
    /// Wróci z Developer ID / wydzieleniem agenta. Patrz `ConfigStore.integrityValid()`.
    func testConfigIntegrityDisabledNoKeychainAccess() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrivioCfg-\(UUID().uuidString)", isDirectory: true)
        let store = ConfigStore(directory: dir)
        var state = PersistedState()
        state.apps = [sampleApp()]
        store.save(state)
        XCTAssertTrue(store.integrityValid())

        // Nawet po ręcznej modyfikacji nie alarmujemy (funkcja wyłączona).
        let configURL = dir.appendingPathComponent("config.json")
        let original = String(data: try! Data(contentsOf: configURL), encoding: .utf8)!
        let tampered = original.replacingOccurrences(of: "Signal", with: "Hacked")
        try! Data(tampered.utf8).write(to: configURL)
        XCTAssertTrue(store.integrityValid())

        // Nie powstaje żaden plik `.hmac` (brak zapisu tagu).
        XCTAssertFalse(FileManager.default.fileExists(atPath: configURL.appendingPathExtension("hmac").path))
    }

    func testEmptyStoreLoadsDefaults() {
        let loaded = tempStore().load()
        XCTAssertTrue(loaded.apps.isEmpty)
        XCTAssertEqual(loaded.configuration.protectionActive, true)
    }

    // MARK: Maszyna stanów / seam

    func testAddPersistsAndLocksByDefault() async {
        let store = tempStore()
        let service = InProcessEnforcementService(store: store)
        await service.addProtectedApp(sampleApp())

        let state = await service.currentState()
        XCTAssertEqual(state.apps.count, 1)
        XCTAssertEqual(state.apps.first?.status, .locked)   // nowe apki startują zablokowane

        // Nowa instancja z tego samego store widzi zapisaną apkę (i znów locked).
        let reloaded = InProcessEnforcementService(store: store)
        let s2 = await reloaded.currentState()
        XCTAssertEqual(s2.apps.count, 1)
        XCTAssertEqual(s2.apps.first?.status, .locked)
    }

    func testDuplicateBundleIDIgnored() async {
        let service = InProcessEnforcementService()
        await service.addProtectedApp(sampleApp())
        await service.addProtectedApp(sampleApp())   // ten sam bundleID
        let state = await service.currentState()
        XCTAssertEqual(state.apps.count, 1)
    }

    func testUnlockThenLockTransitions() async {
        let service = InProcessEnforcementService()
        await service.addProtectedApp(sampleApp())
        var id = await service.currentState().apps[0].id

        await service.markUnlocked(appID: id)
        var s = await service.currentState()
        XCTAssertEqual(s.apps[0].status, .unlocked)

        await service.lock(appID: id, reason: .inactivity)
        s = await service.currentState()
        XCTAssertEqual(s.apps[0].status, .locked)

        id = s.apps[0].id
        _ = id
    }

    func testDisablingProtectionMarksUnprotected() async {
        let service = InProcessEnforcementService()
        await service.addProtectedApp(sampleApp())
        let id = await service.currentState().apps[0].id

        await service.setProtectionEnabled(false, forAppID: id)
        let s = await service.currentState()
        XCTAssertEqual(s.apps[0].status, .unprotected)
        XCTAssertFalse(s.apps[0].app.protectionEnabled)
    }

    func testRemoveApp() async {
        let store = tempStore()
        let service = InProcessEnforcementService(store: store)
        await service.addProtectedApp(sampleApp())
        let id = await service.currentState().apps[0].id
        await service.removeProtectedApp(id: id)
        let after = await service.currentState()
        XCTAssertTrue(after.apps.isEmpty)
        // Usunięcie też jest utrwalone.
        XCTAssertTrue(store.load().apps.isEmpty)
    }

    func testGlobalProtectionInactiveMakesEffectiveUnprotected() {
        let app = sampleApp()
        let effective = ProtectedAppSnapshot.effectiveStatus(
            app: app, rawStatus: .locked, protectionActive: false)
        XCTAssertEqual(effective, .unprotected)

        let active = ProtectedAppSnapshot.effectiveStatus(
            app: app, rawStatus: .locked, protectionActive: true)
        XCTAssertEqual(active, .locked)
    }

    func testActivityPersistsAcrossInstances() async {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrivioActivity-\(UUID().uuidString)", isDirectory: true)
        let activityStore = ActivityStore(directory: dir)

        let service = InProcessEnforcementService(activityStore: activityStore)
        await service.addProtectedApp(sampleApp())          // loguje zdarzenie
        let count = await service.currentState().recentActivity.count
        XCTAssertGreaterThan(count, 0)

        // Nowa instancja z tym samym magazynem widzi zapisaną historię.
        let reloaded = InProcessEnforcementService(activityStore: activityStore)
        let s = await reloaded.currentState()
        XCTAssertEqual(s.recentActivity.count, count)

        await reloaded.clearActivityHistory()
        let after = InProcessEnforcementService(activityStore: activityStore)
        let afterState = await after.currentState()
        XCTAssertTrue(afterState.recentActivity.isEmpty)
    }

    func testActivityLoggedAndCleared() async {
        let service = InProcessEnforcementService()
        await service.addProtectedApp(sampleApp())          // loguje protectionEnabled
        let id = await service.currentState().apps[0].id
        await service.lock(appID: id, reason: .inactivity)  // loguje locked
        var s = await service.currentState()
        XCTAssertGreaterThanOrEqual(s.recentActivity.count, 2)

        await service.clearActivityHistory()
        s = await service.currentState()
        XCTAssertTrue(s.recentActivity.isEmpty)
    }
}
