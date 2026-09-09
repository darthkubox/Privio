import Foundation

/// Implementacja seam‑u działająca w tym samym procesie co UI.
///
/// Cały stan enforcement (lista apek + ulotne statusy + activity) żyje tu, w
/// izolacji aktora. UI dostaje wyłącznie migawki `EnforcementState`. Gdy w
/// przyszłości wydzielimy `PrivioAgent`, ten aktor przeniesie się do procesu
/// agenta, a UI dostanie `XPCEnforcementProxy` implementujący ten sam protokół -
/// bez zmian w rdzeniu.
///
/// Produkcyjna implementacja in-process: monitoruje aktywację i zdarzenia systemowe,
/// ukrywa lub zamyka chronione aplikacje, uruchamia systemowe uwierzytelnianie,
/// obsługuje timery oraz utrwala konfigurację i historię aktywności.
public actor InProcessEnforcementService: EnforcementControlling {

    private var state: EnforcementState
    private var subscribers: [UUID: AsyncStream<EnforcementState>.Continuation] = [:]
    private let clock: PrivioClock
    private let store: ConfigStore?
    private let activityStore: ActivityStore?
    private let monitor: AppActivationMonitoring?
    private let systemMonitor: SystemEventMonitoring?
    private let controller: RunningAppController?
    private let authenticator: BiometricAuthenticating?
    private let scheduler: InactivityScheduling?
    private let failedAttemptRecorder: FailedAttemptRecording?
    /// Lokalny proxy do blokowania stron (Pro). nil w testach/snapshotach.
    private let webProxy: WebProxyServer?
    /// Czy serwer proxy jest uruchomiony w tej sesji.
    private var proxyRunning = false
    /// Czy wykonano już startową synchronizację blokady stron.
    private var didInitialWebSync = false
    private var monitorTask: Task<Void, Never>?
    private var systemTask: Task<Void, Never>?
    /// Aktualny bundleID aplikacji na pierwszym planie (do wykrywania utraty fokusu).
    private var foregroundBundleID: String?
    /// Krótkie okno „cooldown" po anulowaniu - zapobiega pętli anuluj→apka wraca→prompt.
    private var recentlyCancelled: [String: Date] = [:]
    private let cancelCooldown: TimeInterval = 0.8
    private let maxActivityEntries = 200

    /// - Parameters:
    ///   - store: źródło persystencji. Jeśli podane i brak `initialState`, stan
    ///     ładowany jest z dysku, a zmiany są zapisywane.
    ///   - monitor: źródło zdarzeń aktywacji apek (Faza 3). Gdy podane, serwis
    ///     zaczyna egzekwować (ukrywa zablokowane apki po aktywacji).
    ///   - controller: sterowanie apkami (hide/activate/terminate).
    ///   - initialState: nadpisuje ładowanie (podglądy/snapshoty/testy).
    public init(store: ConfigStore? = nil,
                activityStore: ActivityStore? = nil,
                monitor: AppActivationMonitoring? = nil,
                systemMonitor: SystemEventMonitoring? = nil,
                controller: RunningAppController? = nil,
                authenticator: BiometricAuthenticating? = nil,
                scheduler: InactivityScheduling? = nil,
                failedAttemptRecorder: FailedAttemptRecording? = nil,
                webProxy: WebProxyServer? = nil,
                initialState: EnforcementState? = nil,
                clock: PrivioClock = SystemClock()) {
        self.store = store
        self.activityStore = activityStore
        self.monitor = monitor
        self.systemMonitor = systemMonitor
        self.controller = controller
        self.authenticator = authenticator
        self.scheduler = scheduler
        self.failedAttemptRecorder = failedAttemptRecorder
        self.webProxy = webProxy
        self.clock = clock
        if let initialState {
            self.state = initialState
        } else if let store {
            self.state = EnforcementState.loaded(from: store)
        } else {
            self.state = EnforcementState()
        }
        if let activityStore {
            self.state.recentActivity = activityStore.load()   // historia z dysku (sekcja 19)
        }
        if let store {
            self.state.configIntegrityValid = store.integrityValid()   // sekcja 13
        }
    }

    deinit {
        monitorTask?.cancel(); monitor?.stop()
        systemTask?.cancel(); systemMonitor?.stop()
        scheduler?.cancelAll()
    }

    // MARK: - Zdarzenia systemowe (Faza 8: screen lock / sleep / sesja)

    private func runSystemMonitor() async {
        guard let systemMonitor else { return }
        for await event in systemMonitor.start() {
            handleSystem(event)
        }
    }

    /// Wewnętrzne (dla testów): przetwarza zdarzenie systemowe.
    func handleSystem(_ event: SystemEvent) {
        switch event {
        case .screenLocked:
            guard state.configuration.lockAllAfterScreenLock else { break }
            lockApps(reason: .screenLock) { $0.app.lockAfterScreenLock }
        case .willSleep:
            guard state.configuration.lockAllAfterSleep else { break }
            lockApps(reason: .sleep) { $0.app.lockAfterSleep }
        case .sessionResigned:
            // Przełączenie użytkownika (Fast User Switching) - zablokuj wszystkie.
            lockApps(reason: .sessionChange) { _ in true }
        case .screenUnlocked, .didWake, .sessionBecameActive:
            break   // po powrocie apki POZOSTAJĄ zablokowane (sekcja 13)
        }
    }

    /// Blokuje (i ukrywa) chronione apki spełniające predykat; jeden broadcast.
    private func lockApps(reason: ActivityEvent.Reason, where predicate: (ProtectedAppSnapshot) -> Bool) {
        var changed = false
        for idx in state.apps.indices where state.apps[idx].app.protectionEnabled && predicate(state.apps[idx]) {
            let status = state.apps[idx].status
            guard status == .unlocked || status == .authenticating else { continue }
            state.apps[idx].status = .locked
            cancelTimers(state.apps[idx].id)
            controller?.hide(bundleID: state.apps[idx].app.bundleIdentifier)
            log(.locked, reason: reason, app: state.apps[idx].app)
            changed = true
        }
        if changed {
            state.pendingAuthAppID = nil
            broadcast()
        }
    }

    // MARK: - Egzekwowanie na podstawie zdarzeń aktywacji (Faza 3)

    private func runMonitor() async {
        guard let monitor else { return }
        foregroundBundleID = controller?.frontmostBundleID()
        enforceAllLockedOnStartup()   // ukryj już działające, zablokowane apki
        for await event in monitor.start() {
            handle(event)
        }
    }

    /// Lock‑on‑launch: przy starcie Privio ukryj wszystkie chronione apki, które
    /// są już uruchomione i zablokowane (sekcja 13 - po starcie pozostają zablokowane).
    private func enforceAllLockedOnStartup() {
        guard let controller, state.protectionActive else { return }
        for snap in state.apps where snap.app.protectionEnabled && snap.status == .locked {
            if controller.isRunning(bundleID: snap.app.bundleIdentifier) {
                controller.hide(bundleID: snap.app.bundleIdentifier)
            }
        }
    }

    /// Wewnętrzne (dla testów): przetwarza pojedyncze zdarzenie aktywacji.
    func handle(_ event: AppEvent) {
        switch event {
        case .activated(let bundleID):
            handleForegroundChange(to: bundleID)   // bezczynność (sekcja 8)
            enforceForeground(bundleID: bundleID)  // ukryj, jeśli zablokowana
        case .launched(let bundleID):
            enforceForeground(bundleID: bundleID)  // start apki: ukryj, jeśli zablokowana
        case .terminated(let bundleID):
            guard let idx = state.apps.firstIndex(where: { $0.app.bundleIdentifier == bundleID }) else { break }
            cancelTimers(state.apps[idx].id)
            if bundleID == foregroundBundleID { foregroundBundleID = nil }
            // Po zamknięciu apki wróć do stanu zablokowanego - ponowne uruchomienie
            // od razu wymaga Touch ID/hasła (żądanie użytkownika: quit → relaunch = auth).
            if state.apps[idx].app.protectionEnabled, state.apps[idx].status != .unprotected {
                state.apps[idx].status = .locked
                if state.pendingAuthAppID == state.apps[idx].id { state.pendingAuthAppID = nil }
                broadcast()
            }
        }
    }

    /// Gdy chroniona, zablokowana apka staje się aktywna - natychmiast ją ukryj
    /// i poproś o uwierzytelnienie. To rdzeń modelu z sekcji 2 (minimalizacja
    /// okna ekspozycji - pełnej szczelności publiczne API nie gwarantuje).
    private func enforceForeground(bundleID: String) {
        guard state.protectionActive, state.configuration.appBlockingEnabled,
              let idx = state.apps.firstIndex(where: { $0.app.bundleIdentifier == bundleID }),
              state.apps[idx].app.protectionEnabled else { return }

        // Cooldown po anulowaniu: jeśli apka wraca od razu, tylko ukryj (bez
        // ponownego promptu), żeby nie zapętlić i nie zostawić jej na wierzchu.
        if let cancelledAt = recentlyCancelled[bundleID],
           clock.now().timeIntervalSince(cancelledAt) < cancelCooldown {
            controller?.hide(bundleID: bundleID)
            controller?.activateSelf()
            return
        }

        switch state.apps[idx].status {
        case .locked:
            scheduler?.cancel(key: inactivityKey(state.apps[idx].id))
            controller?.hide(bundleID: bundleID)
            state.apps[idx].status = .authenticating
            state.pendingAuthAppID = state.apps[idx].id
            PrivioLog.enforcement.info("Ukryto zablokowaną apkę po aktywacji: \(bundleID, privacy: .public)")
            broadcast()
        case .authenticating:
            // Apka wciąż czeka na auth, a jej okno znów się pojawiło (typowo:
            // dokończyła uruchamianie po pierwszym ukryciu na .launched) - ukryj
            // ponownie, bez zmiany stanu.
            controller?.hide(bundleID: bundleID)
        case .unlocked, .unprotected:
            break
        }
    }

    // MARK: - Bezczynność (sekcja 8)

    private func inactivityKey(_ id: UUID) -> String { "lock-\(id.uuidString)" }
    private func quitKey(_ id: UUID) -> String { "quit-\(id.uuidString)" }

    /// Anuluje oba timery bezczynności (blokada + zamknięcie) dla apki.
    private func cancelTimers(_ id: UUID) {
        scheduler?.cancel(key: inactivityKey(id))
        scheduler?.cancel(key: quitKey(id))
    }

    /// Reaguje na zmianę apki na pierwszym planie: odblokowana chroniona apka,
    /// która traci fokus, zaczyna odliczać do blokady i zamknięcia; powrót resetuje.
    private func handleForegroundChange(to newBundleID: String) {
        let previous = foregroundBundleID
        foregroundBundleID = newBundleID

        // Apka wracająca na pierwszy plan: anuluj oba odliczania (znów aktywna).
        if let idx = state.apps.firstIndex(where: { $0.app.bundleIdentifier == newBundleID }) {
            cancelTimers(state.apps[idx].id)
        }

        // Apka tracąca fokus: jeśli jest chroniona → start odliczania. Auto-quit
        // dotyczy także apki już zablokowanej lub po anulowanym uwierzytelnieniu;
        // ograniczenie do `.unlocked` powodowało, że timer często nie startował.
        guard state.protectionActive, let prev = previous, prev != newBundleID,
              let idx = state.apps.firstIndex(where: { $0.app.bundleIdentifier == prev }),
              state.apps[idx].app.protectionEnabled else { return }
        startInactivity(forIndex: idx)
    }

    private func startInactivity(forIndex idx: Int) {
        let id = state.apps[idx].id
        let app = state.apps[idx].app

        // Timer blokady.
        if let lockSeconds = app.lockAfterInactivity {
            if lockSeconds <= 0 {
                lock(appID: id, reason: .inactivity)   // „immediately"
            } else {
                scheduler?.schedule(key: inactivityKey(id), seconds: lockSeconds) { [weak self] in
                    Task { await self?.inactivityLockFired(id) }
                }
            }
        }

        // Timer zamknięcia (niezależny - działa dalej także po zablokowaniu apki).
        if let quitSeconds = app.quitAfterInactivity, quitSeconds > 0 {
            scheduler?.schedule(key: quitKey(id), seconds: quitSeconds) { [weak self] in
                Task { await self?.inactivityQuitFired(id) }
            }
        }
    }

    private func inactivityLockFired(_ id: UUID) {
        guard let idx = state.apps.firstIndex(where: { $0.id == id }),
              state.apps[idx].status == .unlocked else { return }  // mógł się zmienić
        lock(appID: id, reason: .inactivity)
    }

    /// Auto‑quit (sekcja 10): najpierw łagodne `terminate()`. Force TYLKO za zgodą
    /// użytkownika (`forceQuitIfUnresponsive`), po okresie karencji - bo apka może
    /// mieć niezapisane dane/uploady/renderowanie.
    private func inactivityQuitFired(_ id: UUID) {
        guard let idx = state.apps.firstIndex(where: { $0.id == id }),
              state.apps[idx].app.protectionEnabled else { return }
        let app = state.apps[idx].app
        guard let controller, controller.isRunning(bundleID: app.bundleIdentifier) else { return }

        controller.terminate(bundleID: app.bundleIdentifier, force: false)
        log(.quit, reason: .inactivity, app: app)
        broadcast()

        if app.forceQuitIfUnresponsive {
            let bundleID = app.bundleIdentifier
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 6_000_000_000)   // 6 s karencji
                await self?.forceQuitIfStillRunning(bundleID)
            }
        }
    }

    private func forceQuitIfStillRunning(_ bundleID: String) {
        guard let controller, controller.isRunning(bundleID: bundleID),
              let snap = state.apps.first(where: { $0.app.bundleIdentifier == bundleID }),
              snap.app.forceQuitIfUnresponsive else { return }
        controller.terminate(bundleID: bundleID, force: true)
        PrivioLog.enforcement.notice("Wymuszono zamknięcie nieodpowiadającej apki: \(bundleID, privacy: .public)")
    }

    /// Zapisuje wyłącznie utrwalaną część (apki + ustawienia), nie stan ulotny.
    private func persist() {
        guard let store else { return }
        store.save(PersistedState(apps: state.apps.map(\.app),
                                  webTargets: state.webTargets.map(\.target),
                                  configuration: state.configuration))
    }

    // MARK: - Odczyt stanu

    public func currentState() -> EnforcementState { state }

    public func stateUpdates() -> AsyncStream<EnforcementState> {
        startMonitoringIfNeeded()
        let id = UUID()
        return AsyncStream { continuation in
            subscribers[id] = continuation
            continuation.yield(state)   // natychmiast bieżąca migawka
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(id) }
            }
        }
    }

    /// Monitoring uruchamiamy dopiero po wejściu do izolowanego kontekstu aktora.
    /// Startowanie zadań i zapisywanie ich uchwytów bezpośrednio w `init` jest
    /// niedozwolone w trybie Swift 6 i może prowadzić do wyścigu z inicjalizacją.
    private func startMonitoringIfNeeded() {
        if monitor != nil, monitorTask == nil {
            monitorTask = Task { [weak self] in await self?.runMonitor() }
        }
        if systemMonitor != nil, systemTask == nil {
            systemTask = Task { [weak self] in await self?.runSystemMonitor() }
        }
        performInitialWebSyncIfNeeded()
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }

    private func broadcast() {
        for continuation in subscribers.values {
            continuation.yield(state)
        }
    }

    // MARK: - Lista chronionych apek

    public func addProtectedApp(_ app: ProtectedApp) {
        guard !state.apps.contains(where: { $0.app.bundleIdentifier == app.bundleIdentifier }) else { return }
        // Nowo dodana apka startuje jako zablokowana (żadnego domyślnego „unlocked").
        state.apps.append(ProtectedAppSnapshot(app: app, status: app.protectionEnabled ? .locked : .unprotected))
        state.apps.sort { $0.app.displayName.localizedCaseInsensitiveCompare($1.app.displayName) == .orderedAscending }
        log(.protectionEnabled, reason: .userAction, app: app)
        persist()
        broadcast()
    }

    public func removeProtectedApp(id: UUID) {
        cancelTimers(id)
        state.apps.removeAll { $0.id == id }
        persist()
        broadcast()
    }

    public func updateProtectedApp(_ app: ProtectedApp) {
        guard let idx = state.apps.firstIndex(where: { $0.id == app.id }) else { return }
        let previous = state.apps[idx].app
        state.apps[idx].app = app
        // Wyłączenie ochrony apki → status unprotected; włączenie → locked.
        if !app.protectionEnabled {
            state.apps[idx].status = .unprotected
        } else if state.apps[idx].status == .unprotected {
            state.apps[idx].status = .locked
        }

        // Zmiana timeoutu dla aplikacji, która już działa w tle, ma obowiązywać
        // od razu. Wcześniej nowa wartość zaczynała działać dopiero po ponownym
        // wejściu do aplikacji i kolejnej utracie fokusu.
        let inactivitySettingsChanged = previous.lockAfterInactivity != app.lockAfterInactivity
            || previous.quitAfterInactivity != app.quitAfterInactivity
        if inactivitySettingsChanged {
            cancelTimers(app.id)
            if state.protectionActive,
               app.protectionEnabled,
               foregroundBundleID != app.bundleIdentifier,
               controller?.isRunning(bundleID: app.bundleIdentifier) == true {
                startInactivity(forIndex: idx)
            }
        }
        persist()
        broadcast()
    }

    public func setProtectionEnabled(_ enabled: Bool, forAppID id: UUID) {
        guard let idx = state.apps.firstIndex(where: { $0.id == id }) else { return }
        state.apps[idx].app.protectionEnabled = enabled
        state.apps[idx].status = enabled ? .locked : .unprotected
        if !enabled { cancelTimers(id) }
        log(enabled ? .protectionEnabled : .protectionDisabled, reason: .userAction, app: state.apps[idx].app)
        persist()
        broadcast()
    }

    // MARK: - Sterowanie blokadą

    public func lock(appID: UUID, reason: ActivityEvent.Reason) {
        guard let idx = state.apps.firstIndex(where: { $0.id == appID }),
              state.apps[idx].app.protectionEnabled else { return }
        state.apps[idx].status = .locked
        scheduler?.cancel(key: inactivityKey(appID))
        // Ukryj natychmiast - treść nie powinna zostać widoczna po zablokowaniu.
        controller?.hide(bundleID: state.apps[idx].app.bundleIdentifier)
        log(.locked, reason: reason, app: state.apps[idx].app)
        broadcast()
    }

    public func lockAll(reason: ActivityEvent.Reason) {
        for idx in state.apps.indices where state.apps[idx].app.protectionEnabled {
            state.apps[idx].status = .locked
            controller?.hide(bundleID: state.apps[idx].app.bundleIdentifier)
        }
        log(.locked, reason: reason, app: nil)
        broadcast()
    }

    public func beginAuthentication(appID: UUID) {
        guard let idx = state.apps.firstIndex(where: { $0.id == appID }) else { return }
        // Zanim pojawi się okno auth, upewnij się, że zablokowana treść jest ukryta.
        controller?.hide(bundleID: state.apps[idx].app.bundleIdentifier)
        state.apps[idx].status = .authenticating
        state.pendingAuthAppID = appID
        broadcast()
    }

    public func cancelAuthentication(appID: UUID) {
        guard let idx = state.apps.firstIndex(where: { $0.id == appID }) else { return }
        state.apps[idx].status = .locked          // pozostaje zablokowana i ukryta
        if state.pendingAuthAppID == appID { state.pendingAuthAppID = nil }
        broadcast()
    }

    @discardableResult
    public func authenticate(appID: UUID, preferPassword: Bool = false) async -> Bool {
        guard let idx = state.apps.firstIndex(where: { $0.id == appID }) else { return false }
        let app = state.apps[idx].app
        guard let authenticator else {
            // Brak autentykatora (testy/snapshot) - nie odblokowuj po cichu.
            return false
        }
        // Pokaż stan „authenticating" i upewnij się, że treść jest ukryta.
        state.apps[idx].status = .authenticating
        state.pendingAuthAppID = appID
        controller?.hide(bundleID: app.bundleIdentifier)
        broadcast()

        // preferPassword (przycisk „Use Password") wymusza prompt z opcją hasła.
        let policy: AuthPolicy
        if preferPassword || !app.requireTouchID {
            policy = .passwordOnly
        } else if app.allowPasswordFallback {
            policy = .biometricsOrPassword
        } else {
            policy = .biometricsOnly
        }
        let result = await authenticator.authenticate(
            bundleID: app.bundleIdentifier, appName: app.displayName, policy: policy)

        switch result {
        case .success:
            markUnlocked(appID: appID)
            return true
        case .failed, .canceled, .unavailable:
            // Bez własnego okna: po nieudanej/anulowanej próbie wróć do „locked"
            // i PONOWNIE ukryj - zablokowana apka nie może zostać widoczna.
            // Ponowna aktywacja apki znów poprosi o Touch ID/hasło.
            if let i = state.apps.firstIndex(where: { $0.id == appID }) {
                state.apps[i].status = .locked
                controller?.hide(bundleID: state.apps[i].app.bundleIdentifier)
            }
            var evidencePhotoFilename: String?
            // LocalAuthentication nie ujawnia aplikacji pojedynczych błędnych haseł.
            // Po kilku błędach i zamknięciu panelu zwraca często `.canceled`, dlatego
            // przy jawnym opt-in zapisujemy dowód po każdym promptcie bez sukcesu.
            if state.configuration.captureFailedAttempts {
                switch result {
                case .failed, .canceled:
                    evidencePhotoFilename = await failedAttemptRecorder?.recordFailedAttempt(
                        bundleID: app.bundleIdentifier,
                        appName: app.displayName
                    )
                case .success, .unavailable:
                    break
                }
            }
            log(.authFailed, reason: .authentication, app: app,
                evidencePhotoFilename: evidencePhotoFilename)
            if state.pendingAuthAppID == appID { state.pendingAuthAppID = nil }
            recentlyCancelled[app.bundleIdentifier] = clock.now()   // uruchom cooldown
            // Przejmij fokus do Privio, by anulowana apka nie odzyskała fokusu i
            // nie odkryła się z powrotem (pętla anuluj → apka wraca → prompt).
            controller?.activateSelf()
            broadcast()
            return false
        }
    }

    public func markUnlocked(appID: UUID) {
        guard let idx = state.apps.firstIndex(where: { $0.id == appID }) else { return }
        state.apps[idx].status = .unlocked
        cancelTimers(appID)
        recentlyCancelled[state.apps[idx].app.bundleIdentifier] = nil
        if state.pendingAuthAppID == appID { state.pendingAuthAppID = nil }
        // Po udanym uwierzytelnieniu przywróć i aktywuj chronioną apkę (sekcja 2).
        controller?.activate(bundleID: state.apps[idx].app.bundleIdentifier)
        log(.unlocked, reason: .authentication, app: state.apps[idx].app)
        broadcast()
    }

    // MARK: - Chronione strony WWW (Pro)

    private func webLockKey(_ id: UUID) -> String { "web-lock-\(id.uuidString)" }

    /// Aktualizuje zestaw domen blokowanych przez proxy - SZYBKIE, bez admina (proxy
    /// sprawdza żywy zestaw przy każdym żądaniu). Wołane po każdej zmianie web/locka.
    private func syncWebBlocking() {
        guard let webProxy else { return }
        let active = state.protectionActive && state.configuration.websiteBlockingEnabled
        // Snooze (wstrzymanie z rozszerzenia): moduł zostaje włączony, ale przez
        // czas pauzy NIC nie jest kierowane ani blokowane (PAC=DIRECT). Nie ruszamy
        // systemowego proxy, więc auto‑wznowienie nie wymaga admina.
        let paused = state.isWebProtectionPaused
        let enforcing = active && !paused
        // PAC kieruje przez Privio WSZYSTKIE chronione domeny (żeby re‑lock po
        // bezczynności też je łapał); proxy blokuje tylko te ZABLOKOWANE.
        let configured = active ? state.webTargets.filter { $0.target.protectionEnabled }.map { $0.target.domain } : []
        let routed = enforcing ? state.webTargets.filter { $0.target.protectionEnabled }.map { $0.target.domain } : []
        let locked = enforcing ? state.webTargets.filter { $0.target.protectionEnabled && $0.status == .locked }.map { $0.target.domain } : []
        webProxy.updateProtectionEnabled(active)
        webProxy.updatePausedUntil(paused ? state.webPauseUntil : nil)
        webProxy.updateConfiguredDomains(configured)
        webProxy.updateRoutedDomains(routed)   // treść PAC (serwowana po HTTP)
        webProxy.updateBlockedDomains(locked)  // które kierowane domeny blokować
        PrivioLog.enforcement.info("syncWeb: paused=\(paused, privacy: .public) PAC=[\(routed.joined(separator: ","), privacy: .public)] blok=[\(locked.joined(separator: ","), privacy: .public)]")
    }

    /// Start serwera proxy (bez admina). NIE ustawia systemowego proxy - to robi
    /// jednorazowo przełącznik modułu (setWebsiteBlockingEnabled).
    private func startProxyIfNeeded() {
        guard let webProxy, !proxyRunning else { return }
        proxyRunning = webProxy.start(
            onBlockedHit: { [weak self] domain in
                Task { await self?.handleBlockedHit(domain) }
            },
            onLockRequest: { [weak self] domain in
                Task { await self?.handleExtensionLock(domain) }
            },
            onActivity: { [weak self] domain, isActive in
                Task { await self?.handleExtensionActivity(domain, isActive: isActive) }
            },
            onOpenSettings: { [weak self] in
                Task { await self?.handleOpenSettingsRequest() }
            },
            onProtectRequest: { [weak self] domain in
                Task { await self?.handleProtectRequest(domain) }
            },
            onRelockRequest: { [weak self] domain in
                Task { await self?.handleRelockRequest(domain) }
            },
            onPauseRequest: { [weak self] minutes in
                Task { await self?.handlePauseRequest(minutes) }
            },
            onUnprotectRequest: { [weak self] domain in
                Task { await self?.handleUnprotectRequest(domain) }
            },
            onResumeRequest: { [weak self] in
                Task { await self?.resumeWebsiteProtection() }
            })
    }

    private let webPauseKey = "web-protection-pause"

    /// Rozszerzenie poprosiło o otwarcie panelu Privio. Publikujemy nowy nonce w
    /// stanie - `AppModel` reaguje, podnosząc okno (za bramką Touch ID). Nie
    /// zmienia to żadnej ochrony ani preferencji.
    private func handleOpenSettingsRequest() {
        state.panelOpenRequest = UUID()
        broadcast()
    }

    /// „Chroń tę stronę" z rozszerzenia - dodaje cel z ustawieniami domyślnymi,
    /// jeśli jeszcze nie istnieje. WZMACNIA ochronę, więc bez Touch ID.
    private func handleProtectRequest(_ rawDomain: String) async {
        let normalized = WebTarget.normalize(rawDomain)
        guard !normalized.isEmpty else { return }
        guard !state.webTargets.contains(where: { $0.target.matches(host: normalized) }) else { return }
        await addWebTarget(WebTarget(domain: normalized))
        PrivioLog.enforcement.info("extension: dodano ochronę \(normalized, privacy: .public)")
    }

    /// „Zablokuj teraz" z rozszerzenia - ręczna blokada chronionej domeny.
    private func handleRelockRequest(_ domain: String) async {
        guard let target = state.webTargets.first(where: {
            $0.target.matches(host: domain) && $0.target.protectionEnabled
        }) else { return }
        await lockWebTarget(id: target.id, reason: .userAction)
    }

    /// „Wstrzymaj ochronę" z rozszerzenia - OSŁABIA ochronę, więc wymaga Touch ID.
    /// Publikujemy żądanie w stanie; `AppModel` bramkuje je (authorize) i dopiero
    /// po sukcesie woła `pauseWebsiteProtection`. Sam serwis nic tu nie wyłącza.
    private func handlePauseRequest(_ minutes: Int) {
        // 0 oznacza „do ręcznego wznowienia”. Nadal jest to tylko runtime pause:
        // restart Privio wzmacnia ochronę i automatycznie ją przywraca.
        guard minutes >= 0, state.pendingPauseRequest == nil else { return }
        state.pendingPauseRequest = PauseRequest(minutes: minutes)
        broadcast()
    }

    private func handleUnprotectRequest(_ domain: String) {
        guard state.pendingWebRemovalRequest == nil,
              state.webTargets.contains(where: { $0.target.matches(host: domain) }) else { return }
        state.pendingWebRemovalRequest = WebRemovalRequest(domain: domain)
        broadcast()
    }

    public func clearPendingWebRemovalRequest(id: UUID) async {
        guard state.pendingWebRemovalRequest?.id == id else { return }
        state.pendingWebRemovalRequest = nil
        broadcast()
    }

    /// AppModel zamyka żądanie pauzy (po auth albo anulowaniu).
    public func clearPendingPauseRequest(id: UUID) async {
        guard state.pendingPauseRequest?.id == id else { return }
        state.pendingPauseRequest = nil
        broadcast()
    }

    /// Wstrzymuje ochronę stron na `minutes` (snooze). Wołane WYŁĄCZNIE przez
    /// `AppModel` po udanym Touch ID. Nie rusza systemowego proxy; planer sam
    /// wznowi po czasie. Bez admina.
    public func pauseWebsiteProtection(minutes: Int) async {
        guard minutes >= 0 else { return }
        scheduler?.cancel(key: webPauseKey)
        if minutes == 0 {
            state.webPauseUntil = .distantFuture
        } else {
            let seconds = Double(minutes) * 60
            state.webPauseUntil = Date().addingTimeInterval(seconds)
            scheduler?.schedule(key: webPauseKey, seconds: seconds) { [weak self] in
                Task { await self?.resumeWebsiteProtection() }
            }
        }
        if minutes == 0 {
            PrivioLog.enforcement.info("web: ochrona wstrzymana do ręcznego wznowienia")
        } else {
            PrivioLog.enforcement.info("web: ochrona wstrzymana na \(minutes, privacy: .public) min")
        }
        syncWebBlocking()
        broadcast()
    }

    /// Wznawia ochronę stron (auto po czasie lub ręczne „Wznów"). WZMACNIA ochronę,
    /// więc bez Touch ID.
    public func resumeWebsiteProtection() async {
        guard state.webPauseUntil != nil else { return }
        state.webPauseUntil = nil
        scheduler?.cancel(key: webPauseKey)
        PrivioLog.enforcement.info("web: ochrona wznowiona")
        syncWebBlocking()
        broadcast()
    }

    /// Na starcie: jeśli moduł stron był włączony, uruchamiamy serwer proxy (systemowe
    /// proxy persystuje z poprzedniej sesji, więc bez admina).
    private func performInitialWebSyncIfNeeded() {
        guard !didInitialWebSync else { return }
        didInitialWebSync = true

        guard webProxy != nil else {
            // Brak implementacji proxy nie może zmieniać preferencji użytkownika.
            // Stan modułu przywrócimy, gdy backend znów będzie dostępny.
            PrivioLog.enforcement.error("web proxy unavailable; preserving website protection setting")
            return
        }
        // Lokalny API działa stale, aby rozszerzenie mogło wyczyścić reguły po
        // wyłączeniu modułu oraz zgłaszać swój status w ekranie konfiguracji.
        startProxyIfNeeded()
        syncWebBlocking()
    }

    /// Proxy trafiło na zablokowaną domenę → poproś o Touch ID dla celu (jeśli jeszcze
    /// nie trwa). AppModel podnosi fokus i uruchamia uwierzytelnienie (pendingAuthWebID).
    private func handleBlockedHit(_ domain: String) {
        guard let idx = state.webTargets.firstIndex(where: {
            $0.target.matches(host: domain) && $0.target.protectionEnabled
        }) else { return }
        guard state.webTargets[idx].status == .locked, state.pendingAuthWebID == nil else { return }
        PrivioLog.enforcement.info("web: blocked hit \(domain, privacy: .public) → żądam Touch ID")
        state.webTargets[idx].status = .authenticating
        state.pendingAuthWebID = state.webTargets[idx].id
        broadcast()
    }

    private func handleExtensionLock(_ domain: String) async {
        guard let target = state.webTargets.first(where: {
            $0.target.matches(host: domain) && $0.target.protectionEnabled
        }) else { return }
        await lockWebTarget(id: target.id, reason: .inactivity)
    }

    private func handleExtensionActivity(_ domain: String, isActive: Bool) async {
        guard let target = state.webTargets.first(where: {
            $0.target.matches(host: domain) && $0.target.protectionEnabled && $0.status == .unlocked
        }) else { return }
        if isActive {
            scheduler?.cancel(key: webLockKey(target.id))
        } else if target.target.lockAfterInactivity == 0 {
            await lockWebTarget(id: target.id, reason: .inactivity)
        } else {
            scheduleWebRelock(target.id)
        }
    }

    /// Przełącznik MODUŁU stron. Włączenie ustawia systemowe proxy (JEDNORAZOWY admin)
    /// i startuje serwer; wyłączenie zdejmuje systemowe proxy, ale zostawia lokalny
    /// API dla rozszerzenia (bez przechwytywania ruchu przeglądarki).
    /// Zwraca, czy się powiodło (admin mógł zostać anulowany).
    @discardableResult
    public func setWebsiteBlockingEnabled(_ enabled: Bool) async -> Bool {
        guard state.configuration.websiteBlockingEnabled != enabled else { return true }
        let port = webProxy?.port ?? 8987
        if enabled {
            startProxyIfNeeded()
            // Nie ustawiaj auto‑proxy, jeśli serwer nie słucha.
            guard proxyRunning else { return false }
            // Ustaw listy PAC/blokad ZANIM system pobierze PAC po HTTP.
            state.configuration.websiteBlockingEnabled = true
            syncWebBlocking()
            let ok = await Task.detached {
                do { try SystemWebProxy.enable(port: port); return true } catch { return false }
            }.value
            guard ok else {
                state.configuration.websiteBlockingEnabled = false
                syncWebBlocking()
                return false
            }
            persist(); broadcast()
            return true
        } else {
            let ok = await Task.detached {
                do { try SystemWebProxy.disable(); return true } catch { return false }
            }.value
            guard ok else { return false }
            state.configuration.websiteBlockingEnabled = false
            syncWebBlocking() // rozszerzenie dostanie pustą listę i usunie reguły DNR
            persist(); broadcast()
            return true
        }
    }

    /// Przełącznik MODUŁU aplikacji - gdy wyłączony, żadne apki nie są egzekwowane.
    public func setAppBlockingEnabled(_ enabled: Bool) async {
        state.configuration.appBlockingEnabled = enabled
        persist(); broadcast()
    }

    public func addWebTarget(_ target: WebTarget) async {
        guard !state.webTargets.contains(where: { $0.target.domain == target.domain }) else { return }
        let status: LockStatus = target.protectionEnabled ? .locked : .unprotected
        state.webTargets.append(WebTargetSnapshot(target: target, status: status))
        state.webTargets.sort { $0.target.displayName.localizedCaseInsensitiveCompare($1.target.displayName) == .orderedAscending }
        persist(); broadcast()
        syncWebBlocking()
    }

    public func removeWebTarget(id: UUID) async {
        scheduler?.cancel(key: webLockKey(id))
        state.webTargets.removeAll { $0.id == id }
        if state.pendingAuthWebID == id { state.pendingAuthWebID = nil }
        persist(); broadcast()
        syncWebBlocking()
    }

    public func updateWebTarget(_ target: WebTarget) async {
        guard let idx = state.webTargets.firstIndex(where: { $0.id == target.id }) else { return }
        state.webTargets[idx].target = target
        scheduler?.cancel(key: webLockKey(target.id))
        if state.webTargets[idx].status == .unlocked { scheduleWebRelock(target.id) }
        persist(); broadcast()
        syncWebBlocking()
    }

    public func setProtectionEnabled(_ enabled: Bool, forWebID id: UUID) async {
        guard let idx = state.webTargets.firstIndex(where: { $0.id == id }) else { return }
        state.webTargets[idx].target.protectionEnabled = enabled
        state.webTargets[idx].status = enabled ? .locked : .unprotected
        if !enabled { scheduler?.cancel(key: webLockKey(id)) }
        persist(); broadcast()
        syncWebBlocking()
    }

    public func lockWebTarget(id: UUID, reason: ActivityEvent.Reason) async {
        guard let idx = state.webTargets.firstIndex(where: { $0.id == id }) else { return }
        scheduler?.cancel(key: webLockKey(id))
        guard state.webTargets[idx].status != .locked else { return }
        state.webTargets[idx].status = .locked
        if state.pendingAuthWebID == id { state.pendingAuthWebID = nil }
        broadcast()
        syncWebBlocking()
    }

    public func beginWebAuthentication(id: UUID) async {
        guard let idx = state.webTargets.firstIndex(where: { $0.id == id }) else { return }
        state.webTargets[idx].status = .authenticating
        state.pendingAuthWebID = id
        broadcast()
    }

    public func cancelWebAuthentication(id: UUID) async {
        guard let idx = state.webTargets.firstIndex(where: { $0.id == id }) else { return }
        state.webTargets[idx].status = .locked
        if state.pendingAuthWebID == id { state.pendingAuthWebID = nil }
        broadcast()
    }

    @discardableResult
    public func authenticateWebTarget(id: UUID, preferPassword: Bool = false) async -> Bool {
        guard let idx = state.webTargets.firstIndex(where: { $0.id == id }) else { return false }
        let target = state.webTargets[idx].target
        guard let authenticator else { return false }
        state.webTargets[idx].status = .authenticating
        state.pendingAuthWebID = id
        broadcast()

        let policy: AuthPolicy
        if preferPassword || !target.requireTouchID {
            policy = .passwordOnly
        } else if target.allowPasswordFallback {
            policy = .biometricsOrPassword
        } else {
            policy = .biometricsOnly
        }
        let result = await authenticator.authenticate(reason: "unlock \(target.domain)", policy: policy)
        PrivioLog.enforcement.info("web: auth \(target.domain, privacy: .public) → \(String(describing: result), privacy: .public)")

        if result == .success {
            if let i = state.webTargets.firstIndex(where: { $0.id == id }) {
                state.webTargets[i].status = .unlocked
            }
            if state.pendingAuthWebID == id { state.pendingAuthWebID = nil }
            broadcast()
            syncWebBlocking()        // zdejmij blok tej domeny (jeden prompt admina)
            scheduleWebRelock(id)         // re-lock po bezczynności
            return true
        } else {
            if let i = state.webTargets.firstIndex(where: { $0.id == id }) {
                state.webTargets[i].status = .locked
            }
            if state.pendingAuthWebID == id { state.pendingAuthWebID = nil }
            broadcast()
            return false
        }
    }

    /// Sprząta blokadę stron (deinstalacja / awaryjne czyszczenie): zdejmuje systemowe
    /// proxy (admin) i zatrzymuje serwer. Best‑effort - nie blokuje deinstalacji.
    public func clearWebsiteBlocks() async {
        _ = await Task.detached { try? SystemWebProxy.disable() }.value
        webProxy?.stop(); proxyRunning = false
    }

    private func scheduleWebRelock(_ id: UUID) {
        guard let idx = state.webTargets.firstIndex(where: { $0.id == id }),
              let seconds = state.webTargets[idx].target.lockAfterInactivity, seconds > 0 else { return }
        scheduler?.schedule(key: webLockKey(id), seconds: seconds) { [weak self] in
            Task { await self?.lockWebTarget(id: id, reason: .inactivity) }
        }
    }

    // MARK: - Akcje wrażliwe (sekcja 18)

    public func authenticateForAction(reason: String) async -> Bool {
        guard let authenticator else { return false }
        let result = await authenticator.authenticate(reason: reason, policy: .biometricsOrPassword)
        return result == .success
    }

    // MARK: - Ustawienia globalne

    public func updateConfiguration(_ config: AppConfiguration) {
        state.configuration = config
        state.protectionActive = config.protectionActive
        persist()
        broadcast()
    }

    public func setProtectionActive(_ active: Bool) {
        state.protectionActive = active
        state.configuration.protectionActive = active
        if !active {
            // Globalne wyłączenie ochrony - statusy apek pozostają, ale efektywnie
            // nieegzekwowane (UI pokazuje to przez `effectiveStatus`).
            log(.protectionDisabled, reason: .userAction, app: nil)
        } else {
            log(.protectionEnabled, reason: .userAction, app: nil)
        }
        persist()
        broadcast()
        // Globalny wyłącznik steruje też blokadą stron (proxy sprawdza żywy zestaw).
        syncWebBlocking()
    }

    // MARK: - Activity

    public func clearActivityHistory() {
        state.recentActivity.removeAll()
        activityStore?.save([])
        broadcast()
    }

    // MARK: - Pomocnicze

    private func log(_ kind: ActivityEvent.Kind, reason: ActivityEvent.Reason, app: ProtectedApp?,
                     evidencePhotoFilename: String? = nil) {
        let event = ActivityEvent(
            date: clock.now(),
            kind: kind,
            reason: reason,
            appDisplayName: app?.displayName,
            bundleIdentifier: app?.bundleIdentifier,
            evidencePhotoFilename: evidencePhotoFilename
        )
        state.recentActivity.insert(event, at: 0)
        if state.recentActivity.count > maxActivityEntries {
            state.recentActivity.removeLast(state.recentActivity.count - maxActivityEntries)
        }
        activityStore?.save(state.recentActivity)   // trwała historia (sekcja 19)
    }
}
