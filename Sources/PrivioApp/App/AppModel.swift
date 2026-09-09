import SwiftUI
import AppKit
import LocalAuthentication
import Observation
import PrivioCore

/// Sekcje nawigacji w sidebarze (wg mockupu).
enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case protectedApps
    case websites
    case privacyCurtain
    case vault
    case proximity
    case activity
    case schedules
    case settings
    case about

    var id: String { rawValue }

    /// Sekcje widoczne w sidebarze. „Schedules" jest chwilowo ukryte (placeholder
    /// spoza zakresu MVP) - kod pozostaje, wróci jako osobna faza harmonogramów.
    static var visibleCases: [SidebarSection] {
        allCases.filter { $0 != .schedules }
    }

    var title: String {
        switch self {
        case .protectedApps: return "Protected Apps"
        case .websites:      return "Protected Websites"
        case .privacyCurtain: return "Privacy Curtain"
        case .vault:         return "Private Vault"
        case .proximity:     return "Proximity Lock"
        case .activity:      return "Activity"
        case .schedules:     return "Schedules"
        case .settings:      return "Settings"
        case .about:         return "About"
        }
    }

    var symbol: String {
        switch self {
        case .protectedApps: return "lock.fill"
        case .websites:      return "globe"
        case .privacyCurtain: return "eye.slash.fill"
        case .vault:         return "lock.rectangle.stack.fill"
        case .proximity:     return "dot.radiowaves.left.and.right"
        case .activity:      return "clock"
        case .schedules:     return "calendar"
        case .settings:      return "gearshape"
        case .about:         return "info.circle"
        }
    }
}

/// Akcje osłabiające ochronę - każda wymaga autoryzacji przez `AppModel.authorize`
/// (hardening, sekcja 6). Powód trafia do treści systemowego promptu.
enum SensitiveAction {
    case openPrivio
    case disableProtection
    case quitPrivio
    case removeApp(name: String)
    case disableAppProtection(name: String)
    case disableAutostart
    case weakenSecuritySettings
    case uninstall
    case pauseWebsiteProtection(minutes: Int)
    case removeWebsiteProtection(domain: String)
    case installUpdate

    var reason: String {
        let pl = (Locale.preferredLanguages.first ?? "en").hasPrefix("pl")
        switch self {
        case .openPrivio:
            return pl ? "otworzyć panel Privio" : "open Privio"
        case .disableProtection:
            return pl ? "wyłączyć ochronę Privio" : "disable Privio protection"
        case .quitPrivio:
            return pl ? "zamknąć Privio i wyłączyć ochronę" : "quit Privio and turn off protection"
        case .removeApp(let name):
            return pl ? "usunąć \(name) z ochrony" : "remove \(name) from Privio"
        case .disableAppProtection(let name):
            return pl ? "wyłączyć ochronę \(name)" : "turn off protection for \(name)"
        case .disableAutostart:
            return pl ? "wyłączyć autostart Privio" : "disable Privio autostart"
        case .weakenSecuritySettings:
            return pl ? "osłabić ustawienia ochrony" : "weaken Privio security settings"
        case .uninstall:
            return pl ? "odinstalować Privio" : "uninstall Privio"
        case .pauseWebsiteProtection(let minutes):
            if minutes == 0 {
                return pl ? "wyłączyć ochronę stron do ręcznego wznowienia"
                          : "turn off website protection until manually resumed"
            }
            return pl ? "wstrzymać ochronę stron na \(minutes) min"
                      : "pause website protection for \(minutes) min"
        case .removeWebsiteProtection(let domain):
            return pl ? "usunąć \(domain) z chronionych stron"
                      : "remove \(domain) from protected websites"
        case .installUpdate:
            return pl ? "sprawdzić i zainstalować aktualizację Privio"
                      : "check for and install a Privio update"
        }
    }
}

/// Warstwa prezentacji ponad seam‑em enforcement.
///
/// AppModel jest JEDYNYM miejscem, w którym UI dotyka enforcementu - przez
/// protokół `EnforcementControlling` i strumień `EnforcementState`. Nie zna
/// wewnętrznych usług (AppMonitor/LockManager itd.). Gdy enforcement przeniesie
/// się do agenta XPC, zmieni się tu wyłącznie typ wstrzykniętego `service`.
@MainActor
@Observable
final class AppModel {
    private(set) var state: EnforcementState
    var selectedSection: SidebarSection = .protectedApps {
        didSet { if selectedSection == .activity { markActivitySeen() } }
    }
    var selectedAppID: UUID?
    var searchText: String = ""
    /// Edycja (Free/Pro) - odświeżana z lokalnie zweryfikowanej licencji.
    private(set) var edition: Edition = .free
    /// Czy zaakceptowano bieżącą wersję umowy licencyjnej (pierwsze uruchomienie).
    private(set) var licenseAccepted = false
    /// Dostęp do głównego panelu obowiązuje tylko do zamknięcia jego okna.
    private(set) var mainWindowAccessGranted = false
    private static let acceptedLicenseKey = "privio.acceptedLicenseVersion"
    private static let activitySeenKey = "privio.activityLastSeenAt"
    private(set) var activitySeenAt: Date = .distantPast

    @ObservationIgnored private let service: EnforcementControlling
    @ObservationIgnored private let catalog: ApplicationCatalog
    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var lastPendingAuthID: UUID?
    @ObservationIgnored private var lastPendingAuthWebID: UUID?
    @ObservationIgnored private var lastPanelOpenRequest: UUID?
    @ObservationIgnored private var lastPauseRequestID: UUID?
    @ObservationIgnored private var lastWebRemovalRequestID: UUID?
    /// Licznik żądań otwarcia panelu z rozszerzenia. Widok zawsze żywy
    /// (`MenuBarLabel`) obserwuje zmiany i podnosi okno (za bramką Touch ID).
    private(set) var panelOpenSignal = 0
    /// Niewidoczna kotwica fokusu na czas systemowego promptu (Privio jest accessory).
    @ObservationIgnored private let focusAnchor = AuthFocusAnchor()
    /// Autostart przy logowaniu (SMAppService).
    @ObservationIgnored private let loginItem = LoginItemService()
    /// Licencjonowanie Pro (weryfikacja WYŁĄCZNIE lokalna, bez sieci).
    @ObservationIgnored private let licenseManager = LicenseManager()
    @ObservationIgnored private let updateController = UpdateController()
    @ObservationIgnored private let privacyModeHotKey = PrivacyModeHotKey()
    @ObservationIgnored private let privacyCurtain = PrivacyCurtainController()
    /// Zasłona blokady - druga warstwa ochrony: zakrywa okna zablokowanych apek, gdy
    /// systemowe ukrycie (`hide()`) zawiedzie (np. tryb pełnoekranowy). Zawsze aktywna.
    @ObservationIgnored private let lockCover = LockCoverController()
    /// Hak do `ProximityController` (moduł „Blokada po odejściu") - wołany z bieżącą
    /// konfiguracją proximity przy starcie i na każdej migawce stanu. Kontroler żyje
    /// w warstwie aplikacji (potrzebuje ekranu/sejfu), więc dostaje config przez ten hak.
    @ObservationIgnored var onProximityConfig: ((ProximityConfig) -> Void)?

    init(service: EnforcementControlling,
         initialState: EnforcementState = EnforcementState(),
         catalog: ApplicationCatalog = ApplicationCatalog()) {
        self.service = service
        self.state = initialState
        self.catalog = catalog
        self.licenseAccepted = UserDefaults.standard.integer(forKey: Self.acceptedLicenseKey) >= LicenseAgreement.version
        self.activitySeenAt = UserDefaults.standard.object(forKey: Self.activitySeenKey) as? Date ?? .distantPast
    }

    /// Zatwierdzenie umowy licencyjnej przy pierwszym uruchomieniu.
    func acceptLicense() {
        UserDefaults.standard.set(LicenseAgreement.version, forKey: Self.acceptedLicenseKey)
        licenseAccepted = true
    }

    /// Aktualizacja podmienia binarkę apki‑lockera, więc - jak inne wrażliwe akcje -
    /// wymaga Touch ID/hasła, zanim Sparkle w ogóle sprawdzi i zainstaluje update.
    func checkForUpdates() {
        Task { if await authorize(.installUpdate) { updateController.checkForUpdates() } }
    }

    /// Subskrypcja strumienia migawek. Wołane raz z `.task` w RootView.
    // MARK: - Status ochrony (sekcje 23-24: nie kłam o stanie ochrony)

    /// Czy biometria (Touch ID) jest dostępna na tym Macu.
    var touchIDAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    var loginItemEnabled: Bool { state.configuration.startAtLogin }

    var protectedCount: Int { state.apps.filter { $0.app.protectionEnabled }.count }

    /// Źródło identyfikatorów aktualnie uruchomionych procesów. Domyślnie system
    /// (NSWorkspace); w trybie snapshot podmieniane, by podejrzeć listę bez
    /// realnie działających apek.
    @ObservationIgnored var runningBundleIDsProvider: () -> Set<String> = {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    /// Skonfigurowane apki, które są teraz uruchomione - do „na żywo" listy w
    /// pasku menu (co jest otwarte i czy jest zablokowane). Odczyt listy procesów
    /// to zwykłe zapytanie systemu, więc nie przechodzi przez seam enforcementu;
    /// kolejność zachowuje kolejność z listy chronionych apek.
    var runningApps: [ProtectedAppSnapshot] {
        let runningIDs = runningBundleIDsProvider()
        return state.apps.filter { runningIDs.contains($0.app.bundleIdentifier) }
    }

    var privacyModeEnabled: Bool { state.configuration.privacyModeEnabled }
    var unreadSecurityEventCount: Int {
        state.recentActivity.filter { $0.kind == .authFailed && $0.date > activitySeenAt }.count
    }
    private(set) var lockedRevealActive = false

    // MARK: - Licencjonowanie (Free/Pro; weryfikacja lokalna)

    var isPro: Bool { edition == .pro }
    var licenseInfo: LicensePayload? { licenseManager.licenseInfo() }

    func refreshLicense() { edition = licenseManager.currentEdition() }

    /// Wyłącznie dla trybu snapshot (podgląd UI funkcji Pro) - nie używać w produkcji.
    func snapshotOverrideEdition(pro: Bool) { edition = pro ? .pro : .free }

    /// „Activate Pro" = LOKALna weryfikacja podpisu licencji (nie aktywacja sieciowa).
    @discardableResult
    func activatePro(_ key: String) -> ActivationResult {
        let result = licenseManager.activate(key)
        refreshLicense()
        return result
    }

    func removeLicense() {
        licenseManager.deactivate()
        refreshLicense()
    }

    func startObserving() {
        guard observationTask == nil else { return }
        refreshLicense()
        repairLoginItemRegistrationAfterUpdate()
        reconcileLoginItem()
        configurePrivacyModeHotKey()
        updatePrivacyCurtain(with: state)
        lockCover.update(with: state)
        onProximityConfig?(state.configuration.proximity)
        observationTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.service.stateUpdates()
            for await newState in stream {
                self.state = newState
                self.configurePrivacyModeHotKey()
                self.updatePrivacyCurtain(with: newState)
                // Zasłona blokady PRZED syncAuth: nakładka wstaje synchronicznie, zanim
                // (po ~120 ms) pojawi się systemowy prompt Touch ID nad oknem apki.
                self.lockCover.update(with: newState)
                self.onProximityConfig?(newState.configuration.proximity)
                // Utrzymaj sensowną selekcję na liście apek.
                if self.selectedAppID == nil || !newState.apps.contains(where: { $0.id == self.selectedAppID }) {
                    self.selectedAppID = newState.apps.first?.id
                }
                self.syncAuth(with: newState)
                self.syncWebAuth(with: newState)
                self.syncPanelOpen(with: newState)
                self.syncPauseRequest(with: newState)
                self.syncWebRemovalRequest(with: newState)
            }
        }
    }

    /// Once per installed build, make sure SMAppService points at
    /// /Applications/Privio.app rather than a previously launched DerivedData copy.
    private func repairLoginItemRegistrationAfterUpdate() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let key = "privio.loginItem.repairedBuild"
        guard !version.isEmpty, UserDefaults.standard.string(forKey: key) != version else { return }
        if loginItem.isEnabled { _ = loginItem.refreshInstalledRegistration() }
        if Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL.path == "/Applications/Privio.app" {
            UserDefaults.standard.set(version, forKey: key)
        }
    }

    /// Rozszerzenie poprosiło o wstrzymanie ochrony (osłabia ochronę → Touch ID).
    /// Podnosimy fokus (Privio jest w tle), bramkujemy `authorize`, i dopiero po
    /// sukcesie wołamy `pauseWebsiteProtection`. Potem wracamy do przeglądarki.
    private func syncPauseRequest(with newState: EnforcementState) {
        let request = newState.pendingPauseRequest
        guard request?.id != lastPauseRequestID else { return }
        lastPauseRequestID = request?.id
        guard let request else { return }
        let previousApp = NSWorkspace.shared.frontmostApplication
        Task {
            focusAnchor.present()
            try? await Task.sleep(nanoseconds: 120_000_000)
            if await authorize(.pauseWebsiteProtection(minutes: request.minutes)) {
                await service.pauseWebsiteProtection(minutes: request.minutes)
            }
            await service.clearPendingPauseRequest(id: request.id)
            focusAnchor.dismiss()
            previousApp?.activate()
        }
    }

    private func syncWebRemovalRequest(with newState: EnforcementState) {
        let request = newState.pendingWebRemovalRequest
        guard request?.id != lastWebRemovalRequestID else { return }
        lastWebRemovalRequestID = request?.id
        guard let request else { return }
        let previousApp = NSWorkspace.shared.frontmostApplication
        Task {
            focusAnchor.present()
            try? await Task.sleep(nanoseconds: 120_000_000)
            if await authorize(.removeWebsiteProtection(domain: request.domain)),
               let target = state.webTargets.first(where: { $0.target.matches(host: request.domain) }) {
                await service.removeWebTarget(id: target.id)
            }
            await service.clearPendingWebRemovalRequest(id: request.id)
            focusAnchor.dismiss()
            previousApp?.activate()
        }
    }

    /// Do kiedy ochrona stron jest wstrzymana (dla UI), albo nil.
    var webProtectionPausedUntil: Date? { state.isWebProtectionPaused ? state.webPauseUntil : nil }

    /// Ręczne wznowienie ochrony stron (WZMACNIA ochronę → bez Touch ID).
    func resumeWebProtection() {
        Task { await service.resumeWebsiteProtection() }
    }

    /// Rozszerzenie poprosiło o otwarcie panelu (nowy `panelOpenRequest`). Ustawiamy
    /// sekcję na „Strony" i budzimy widok, który wykona bramkowaną autoryzacją
    /// prezentację okna. Gwardia zapobiega powtórce dla tego samego nonce.
    private func syncPanelOpen(with newState: EnforcementState) {
        let request = newState.panelOpenRequest
        guard request != lastPanelOpenRequest else { return }
        lastPanelOpenRequest = request
        guard request != nil else { return }
        selectedSection = .websites
        panelOpenSignal &+= 1
    }

    /// Reaguje na żądanie auth: pokazujemy WYŁĄCZNIE systemowy prompt Touch ID
    /// (bez własnego okna - jeden ekran). Aktywujemy Privio, by prompt dostał
    /// fokus, i uruchamiamy uwierzytelnienie. Gwardia zapobiega podwójnemu
    /// odpaleniu, gdy enforcement rozgłasza ten sam `pendingAuthAppID`.
    private func syncAuth(with newState: EnforcementState) {
        let pending = newState.pendingAuthAppID
        guard pending != lastPendingAuthID else { return }
        lastPendingAuthID = pending
        guard let pending, newState.apps.contains(where: { $0.id == pending }) else {
            focusAnchor.dismiss()
            return
        }
        // Niewidoczna kotwica: aktywuje Privio i przekazuje fokus systemowemu
        // promptowi (accessory app bez okna sam nie dostałby fokusu).
        focusAnchor.present()
        // Polityka wg wyboru per aplikacja (Touch ID lub hasło / tylko Touch ID) -
        // sam serwis wybiera na podstawie ustawienia apki. Krótkie opóźnienie daje
        // aktywacji czas, by prompt pojawił się z fokusem (palec od razu).
        Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            await service.authenticate(appID: pending, preferPassword: false)
        }
    }

    /// Analogicznie do `syncAuth`, ale dla stron: gdy proxy trafi na zablokowaną
    /// domenę, enforcement ustawia `pendingAuthWebID` → tu podnosimy fokus i prosimy
    /// o Touch ID. Po odblokowaniu proxy przepuszcza (użytkownik odświeża stronę).
    private func syncWebAuth(with newState: EnforcementState) {
        let pending = newState.pendingAuthWebID
        guard pending != lastPendingAuthWebID else { return }
        lastPendingAuthWebID = pending
        guard let pending, newState.webTargets.contains(where: { $0.id == pending }) else {
            focusAnchor.dismiss()
            return
        }
        // Zapamiętaj aktywną apkę (przeglądarkę) SPRZED podniesienia fokusu, żeby po
        // odblokowaniu do niej wrócić (nie zostawiać Privio na wierzchu).
        let previousApp = NSWorkspace.shared.frontmostApplication
        // Odraczamy do kolejnego cyklu (Task), żeby manipulacja oknem/fokusem nie
        // działa się RE‑ENTRANTNIE w trakcie aktualizacji stanu SwiftUI.
        Task {
            focusAnchor.present()
            try? await Task.sleep(nanoseconds: 120_000_000)
            _ = await service.authenticateWebTarget(id: pending, preferPassword: false)
            focusAnchor.dismiss()
            // Wróć do przeglądarki - użytkownik ma zostać tam, gdzie był.
            previousApp?.activate()
        }
    }

    // MARK: - Pochodne widoki

    var filteredApps: [ProtectedAppSnapshot] {
        guard !searchText.isEmpty else { return state.apps }
        let q = searchText.lowercased()
        return state.apps.filter {
            $0.app.displayName.lowercased().contains(q)
            || $0.app.bundleIdentifier.lowercased().contains(q)
        }
    }

    var selectedSnapshot: ProtectedAppSnapshot? {
        guard let id = selectedAppID else { return state.apps.first }
        return state.apps.first { $0.id == id } ?? state.apps.first
    }

    func effectiveStatus(_ snapshot: ProtectedAppSnapshot) -> LockStatus {
        ProtectedAppSnapshot.effectiveStatus(
            app: snapshot.app,
            rawStatus: snapshot.status,
            protectionActive: state.protectionActive && state.configuration.appBlockingEnabled)
    }

    /// Bundle IDs już chronionych apek (do odfiltrowania w „Add Application").
    var protectedBundleIDs: Set<String> {
        Set(state.apps.map(\.app.bundleIdentifier))
    }

    /// Skan zainstalowanych aplikacji w tle (katalog + wyszukiwarka, sekcja 6).
    func scanInstalledApps() async -> [InstalledApp] {
        let catalog = self.catalog
        return await Task.detached(priority: .userInitiated) { catalog.scan() }.value
    }

    /// Tworzy chronioną apkę z domyślnymi ustawieniami z konfiguracji globalnej.
    func makeProtectedApp(from installed: InstalledApp) -> ProtectedApp {
        let c = state.configuration
        return ProtectedApp(
            bundleIdentifier: installed.bundleIdentifier,
            displayName: installed.displayName,
            applicationURL: installed.url,
            lockAfterInactivity: c.defaultLockTimeout,
            quitAfterInactivity: c.defaultQuitTimeout,
            lockAfterScreenLock: c.lockAllAfterScreenLock,
            lockAfterSleep: c.lockAllAfterSleep,
            requireTouchID: c.defaultRequireTouchID,
            allowPasswordFallback: c.defaultAllowPasswordFallback)
    }

    // MARK: - Akcje (forwardowane do seam-u)

    /// Włączenie ochrony - od ręki. Wyłączenie WYMAGA uwierzytelnienia (sekcja 18):
    /// Privio nie może zostać wyłączone bez Touch ID/hasła.
    /// Jedna centralna bramka autoryzacji akcji wrażliwych (hardening, sekcja 6):
    /// wszystkie osłabienia ochrony przechodzą tędy (Touch ID/hasło via seam).
    /// TRUE w trakcie systemowego promptu uwierzytelniania. `showMainWindowOnLaunch`
    /// (delegat) sprawdza tę flagę, by NIE aktywować okna Privio w trakcie promptu -
    /// inaczej aktywacja odbierała front UIAgentowi Touch ID i prompt gasł.
    @MainActor static var authInProgress = false

    func authorize(_ action: SensitiveAction) async -> Bool {
        AppModel.authInProgress = true
        defer { AppModel.authInProgress = false }
        // Bez kotwicy fokusu systemowy prompt Touch ID nie pokazuje się, gdy akcję
        // wyzwolono z paska menu (Privio to accessory bez okna) - dlatego „Zamknij"
        // i „Sprawdź aktualizacje" wisiały. Kotwica jest liczona (bezpieczne zagnieżdżenie).
        // Gdy jest WIDOCZNE okno panelu (np. ekran blokady), używamy JEGO jako okna
        // kluczowego i NIE pokazujemy kotwicy 1×1. Kotwica robiła kluczowym swój mały
        // panel; po pojawieniu się promptu główne okno odbierało mu fokus - stąd „prompt
        // dostaje fokus, potem przechodzi na Privio". Z jednym oknem kluczowym prompt go
        // zachowuje. Kotwica zostaje tylko dla akcji BEZ okna (accessory, pasek menu).
        // TEMP DIAG: sampler okna kluczowego/frontu w trakcie autoryzacji (openPrivio).
        let diag = action.reason.isEmpty ? nil : Task { @MainActor in
            for i in 0..<40 { PrivioAuthDiag.log(PrivioAuthDiag.snapshot("t\(i)")); try? await Task.sleep(nanoseconds: 100_000_000) }
        }
        defer { diag?.cancel() }
        PrivioAuthDiag.log("=== authorize \(String(describing: action)) === " + PrivioAuthDiag.snapshot("before"))

        if let panelWindow = NSApp.windows.first(where: {
            $0.isVisible && $0.canBecomeMain && !($0 is KeyablePanel)
        }) {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            panelWindow.makeKeyAndOrderFront(nil)
            PrivioAuthDiag.log("path=window " + PrivioAuthDiag.snapshot("after-makeKey"))
            let r = await service.authenticateForAction(reason: action.reason)
            PrivioAuthDiag.log("result=\(r) " + PrivioAuthDiag.snapshot("after-eval"))
            return r
        }
        PrivioAuthDiag.log("path=anchor " + PrivioAuthDiag.snapshot("before-anchor"))

        focusAnchor.present()
        defer { focusAnchor.dismiss() }
        // Poczekaj, aż Privio FAKTYCZNIE stanie się aplikacją frontmost, zanim pokażemy
        // systemowy prompt (accessory bez okna nie zawsze da się aktywować od razu).
        await Task.yield()
        let myBundleID = Bundle.main.bundleIdentifier
        for _ in 0..<40 {   // do ~2 s; gdy już frontmost - przerywamy natychmiast
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == myBundleID { break }
            NSApp.activate(ignoringOtherApps: true)
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return await service.authenticateForAction(reason: action.reason)
    }

    /// Każde ponowne otwarcie panelu Privio wymaga systemowego Touch ID lub
    /// hasła Maca. Już otwarte okno nie wyświetla kolejnych promptów.
    func unlockMainWindow() async -> Bool {
        if mainWindowAccessGranted { return true }
        let granted = await authorize(.openPrivio)
        mainWindowAccessGranted = granted
        return granted
    }

    func lockMainWindow() {
        mainWindowAccessGranted = false
    }

    /// Auto‑odblokowanie panelu przy starcie - TYLKO gdy Privio jest realnie aplikacją
    /// frontmost. Po restarcie przez aktualizator Sparkle macOS nie pozwala apce
    /// uruchomionej przez relauncher przejąć frontu, więc auto‑prompt Touch ID lądował
    /// w tle (bez fokusu). W takim wypadku NIE pokazujemy promptu - zostaje ekran
    /// blokady z przyciskiem „Odblokuj Privio". Klik użytkownika gwarantuje, że Privio
    /// jest na froncie, więc kolejny prompt ma fokus. Normalne uruchomienie (podwójny
    /// klik apki = frontmost) dalej odblokowuje automatycznie.
    func unlockMainWindowWhenFrontmost() {
        guard !mainWindowAccessGranted else { return }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier else { return }
        Task { _ = await unlockMainWindow() }
    }

    func setProtectionActive(_ active: Bool) {
        if active {
            Task { await service.setProtectionActive(true) }
        } else {
            Task { if await authorize(.disableProtection) { await service.setProtectionActive(false) } }
        }
    }

    // MARK: - Privacy Mode (osobny moduł: rozmycie okien chronionych apek)

    func setPrivacyModeEnabled(_ enabled: Bool) {
        var config = state.configuration
        config.privacyModeEnabled = enabled
        Task { await service.updateConfiguration(config) }
    }

    func togglePrivacyMode() {
        setPrivacyModeEnabled(!privacyModeEnabled)
    }

    var privacyCurtainMode: PrivacyCurtainMode { state.configuration.privacyCurtainMode }
    var privacyCurtainScope: PrivacyCurtainScope { state.configuration.privacyCurtainScope }

    func setPrivacyCurtainMode(_ mode: PrivacyCurtainMode) {
        var config = state.configuration
        config.privacyCurtainMode = mode
        Task { await service.updateConfiguration(config) }
    }

    func setPrivacyCurtainScope(_ scope: PrivacyCurtainScope) {
        var config = state.configuration
        config.privacyCurtainScope = scope
        Task { await service.updateConfiguration(config) }
    }

    private func configurePrivacyModeHotKey() {
        privacyModeHotKey.register(identifier: state.configuration.privacyModeShortcut) { [weak self] in
            self?.togglePrivacyMode()
        }
        privacyModeHotKey.registerRevealHold(
            identifier: state.configuration.privacyRevealHoldShortcut,
            pressed: { [weak self] in self?.privacyCurtain.setHoldRevealActive(true) },
            released: { [weak self] in self?.privacyCurtain.setHoldRevealActive(false) }
        )
    }

    private func updatePrivacyCurtain(with state: EnforcementState) {
        privacyCurtain.update(configuration: state.configuration, apps: state.apps)
        lockedRevealActive = privacyCurtain.lockedReveal
    }

    /// Zamknięcie Privio - jeśli ochrona jest aktywna, wymaga uwierzytelnienia
    /// (inaczej dałoby się po cichu wyłączyć ochronę zamykając apkę - sekcja 18).
    func requestQuit() {
        guard state.protectionActive else { NSApp.terminate(nil); return }
        Task { if await authorize(.quitPrivio) { NSApp.terminate(nil) } }
    }

    /// Oficjalny przepływ odinstalowania (sekcja 11): auth → wyrejestrowanie
    /// autostartu → usunięcie danych Privio (config, activity, licencja) →
    /// przeniesienie .app do Kosza → zamknięcie. NIE usuwa danych innych apek i
    /// NIE utrudnia właścicielowi usunięcia.
    func uninstall() {
        Task {
            guard await authorize(.uninstall) else { return }
            loginItem.setEnabled(false)
            licenseManager.deactivate()
            await service.clearWebsiteBlocks()   // zdejmij blok /etc/hosts (inaczej strony zostają zablokowane)
            let dir = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Privio", isDirectory: true)
            try? FileManager.default.removeItem(at: dir)
            _ = try? await NSWorkspace.shared.recycle([Bundle.main.bundleURL])
            NSApp.terminate(nil)
        }
    }

    /// Włączenie autostartu - od ręki; WYŁĄCZENIE wymaga autoryzacji (sekcja 10).
    func setStartAtLogin(_ enabled: Bool) {
        if enabled {
            applyStartAtLogin(true)
        } else {
            Task { if await authorize(.disableAutostart) { applyStartAtLogin(false) } }
        }
    }

    private func applyStartAtLogin(_ enabled: Bool) {
        let actual = loginItem.setEnabled(enabled)   // faktyczny stan po rejestracji
        var config = state.configuration
        config.startAtLogin = actual
        Task { await service.updateConfiguration(config) }
    }

    /// Uzgadnia zapisany `startAtLogin` z faktycznym stanem SMAppService (np. gdy
    /// użytkownik zmienił go w Ustawieniach systemowych).
    private func reconcileLoginItem() {
        let actual = loginItem.isEnabled
        guard actual != state.configuration.startAtLogin else { return }
        var config = state.configuration
        config.startAtLogin = actual
        Task { await service.updateConfiguration(config) }
    }

    func updateConfiguration(_ config: AppConfiguration) {
        let current = state.configuration
        if SecurityChangeAssessment.weakensProtection(from: current, to: config) {
            Task {
                if await authorize(.weakenSecuritySettings) {
                    await service.updateConfiguration(config)
                }
            }
        } else {
            Task { await service.updateConfiguration(config) }
        }
    }

    /// Jawne włączenie kamery: zgodę pokazuje macOS w chwili przełączenia, nie
    /// dopiero przy nieudanej próbie. Zwraca false, gdy użytkownik odmówił.
    func setCaptureFailedAttempts(_ enabled: Bool) async -> Bool {
        if enabled, !(await CameraFailedAttemptRecorder.requestAuthorization()) {
            return false
        }
        var config = state.configuration
        config.captureFailedAttempts = enabled
        await service.updateConfiguration(config)
        return true
    }

    /// macOS nie pozwala ponowić systemowego promptu po wcześniejszej odmowie.
    /// Otwieramy więc bezpośrednio właściwy panel, bez zmuszania użytkownika do
    /// ręcznego szukania go w Ustawieniach systemowych.
    func openCameraPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Otwiera Ustawienia systemowe → Powiadomienia, zakotwiczone (o ile macOS to
    /// honoruje) na danej apce - skrót do szybkiego wyłączenia powiadomień, które
    /// mogą zdradzać treść chronionej apki mimo blokady (podglądy na ekranie).
    func openNotificationSettings(for app: ProtectedApp) {
        let anchor = app.bundleIdentifier
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications?id=\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    func revealFailedAttemptPhotos() {
        let directory = CameraFailedAttemptRecorder.photosDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    func clearFailedAttemptPhotos() {
        let directory = CameraFailedAttemptRecorder.photosDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for file in files where file.pathExtension.lowercased() == "jpg" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    func failedAttemptPhotoURL(for event: ActivityEvent) -> URL? {
        if let filename = event.evidencePhotoFilename,
           filename == URL(fileURLWithPath: filename).lastPathComponent {
            let url = CameraFailedAttemptRecorder.photosDirectory.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }

        // Migracja zdjęć z wersji, które nie zapisywały nazwy pliku w ActivityEvent.
        guard event.kind == .authFailed, let bundleID = event.bundleIdentifier else { return nil }
        let safeBundleID = bundleID.replacingOccurrences(of: "/", with: "-")
        let directory = CameraFailedAttemptRecorder.photosDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]
        ) else { return nil }
        return files
            .filter { $0.pathExtension.lowercased() == "jpg" && $0.lastPathComponent.contains(safeBundleID) }
            .compactMap { url -> (URL, TimeInterval)? in
                guard let date = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate else { return nil }
                let distance = abs(date.timeIntervalSince(event.date))
                return distance <= 30 ? (url, distance) : nil
            }
            .min(by: { $0.1 < $1.1 })?.0
    }

    func markActivitySeen() {
        activitySeenAt = Date()
        UserDefaults.standard.set(activitySeenAt, forKey: Self.activitySeenKey)
    }

    /// Włączenie ochrony apki - od ręki; WYŁĄCZENIE wymaga autoryzacji (sekcja 6).
    func setProtectionEnabled(_ enabled: Bool, for app: ProtectedApp) {
        if enabled {
            Task { await service.setProtectionEnabled(true, forAppID: app.id) }
        } else {
            Task {
                if await authorize(.disableAppProtection(name: app.displayName)) {
                    await service.setProtectionEnabled(false, forAppID: app.id)
                }
            }
        }
    }

    func updateApp(_ app: ProtectedApp) {
        guard let current = state.apps.first(where: { $0.id == app.id })?.app else { return }
        if SecurityChangeAssessment.weakensProtection(from: current, to: app) {
            Task {
                if await authorize(.weakenSecuritySettings) {
                    await service.updateProtectedApp(app)
                }
            }
        } else {
            Task { await service.updateProtectedApp(app) }
        }
    }

    /// Usunięcie apki z ochrony wymaga autoryzacji (sekcja 6).
    func removeApp(_ app: ProtectedApp) {
        Task {
            if await authorize(.removeApp(name: app.displayName)) {
                await service.removeProtectedApp(id: app.id)
            }
        }
    }

    func addApp(_ app: ProtectedApp) {
        Task { await service.addProtectedApp(app) }
    }

    // MARK: - Chronione strony WWW (Pro)

    var webTargets: [WebTargetSnapshot] { state.webTargets }

    /// Dodaje stronę z wpisanego adresu (normalizacja URL→domena w `WebTarget`).
    /// Blokada stron to funkcja Pro.
    func addWebTarget(_ input: String) {
        guard isPro else { return }
        let domain = WebTarget.normalize(input)
        guard !domain.isEmpty, domain.contains(".") else { return }
        Task { await service.addWebTarget(WebTarget(domain: domain)) }
    }

    func removeWebTarget(_ target: WebTarget) {
        Task {
            if await authorize(.removeApp(name: target.displayName)) {
                await service.removeWebTarget(id: target.id)
            }
        }
    }

    func updateWebTarget(_ target: WebTarget) {
        Task { await service.updateWebTarget(target) }
    }

    func setWebProtectionEnabled(_ enabled: Bool, for target: WebTarget) {
        if enabled {
            Task { await service.setProtectionEnabled(true, forWebID: target.id) }
        } else {
            Task {
                if await authorize(.disableAppProtection(name: target.displayName)) {
                    await service.setProtectionEnabled(false, forWebID: target.id)
                }
            }
        }
    }

    /// Odblokowanie strony: Touch ID/hasło → Privio zdejmuje wpis z `/etc/hosts`
    /// (jeden prompt administratora), a strona re-lockuje się po bezczynności.
    func unlockWebTarget(_ target: WebTarget, preferPassword: Bool = false) {
        Task {
            focusAnchor.present()
            try? await Task.sleep(nanoseconds: 120_000_000)
            _ = await service.authenticateWebTarget(id: target.id, preferPassword: preferPassword)
            focusAnchor.dismiss()
        }
    }

    func lockWebTarget(_ target: WebTarget) {
        Task { await service.lockWebTarget(id: target.id, reason: .userAction) }
    }

    /// Kopiuje dołączony folder wtyczki (`ChromeExtension`/`FirefoxExtension`) do
    /// `~/Library/Application Support/Privio/<name>` jako rozpakowaną wersję i zwraca
    /// jej lokalizację. Źródło: zasoby aplikacji, a w devie - katalog roboczy.
    @discardableResult
    private func stageBundledExtension(named name: String) -> URL? {
        let fm = FileManager.default
        let bundled = Bundle.main.resourceURL?.appendingPathComponent(name, isDirectory: true)
        let development = URL(fileURLWithPath: fm.currentDirectoryPath)
            .appendingPathComponent(name, isDirectory: true)
        guard let source = [bundled, development].compactMap({ $0 }).first(where: {
            fm.fileExists(atPath: $0.appendingPathComponent("manifest.json").path)
        }), let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }

        let parent = support.appendingPathComponent("Privio", isDirectory: true)
        let destination = parent.appendingPathComponent(name, isDirectory: true)
        do {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.copyItem(at: source, to: destination)
            return destination
        } catch {
            PrivioLog.enforcement.error("extension staging failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Ścieżka, w której użytkownik znajdzie rozpakowane pliki wtyczki (do pokazania w UI).
    func extensionFolderPath(named name: String) -> String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return support?.appendingPathComponent("Privio/\(name)", isDirectory: true).path
            ?? "~/Library/Application Support/Privio/\(name)"
    }

    /// Sam kopiuje pliki wtyczki i pokazuje je w Finderze (bez otwierania przeglądarki).
    func revealExtensionFolder(named name: String) {
        guard let destination = stageBundledExtension(named: name) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }

    /// Przygotowuje aktualną, dołączoną do Privio wersję rozszerzenia jako folder
    /// „unpacked”, pokazuje go w Finderze i otwiera stronę rozszerzeń Chrome.
    func openChromeExtensionSetup() {
        guard let destination = stageBundledExtension(named: "ChromeExtension") else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destination])
        if let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome"),
           let extensionsURL = URL(string: "chrome://extensions") {
            NSWorkspace.shared.open([extensionsURL], withApplicationAt: chrome,
                                    configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Jak wyżej, ale dla Firefoksa: kopiuje dołączony folder wtyczki, pokazuje go w
    /// Finderze i otwiera stronę tymczasowych dodatków Firefoksa (about:debugging).
    /// Firefox nie ma `chrome://extensions`; wtyczka ładuje się jako „Load Temporary
    /// Add-on" (do czasu podpisania na addons.mozilla.org).
    func openFirefoxExtensionSetup() {
        guard let destination = stageBundledExtension(named: "FirefoxExtension") else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destination])
        // UWAGA: bez fragmentu `#/runtime/this-firefox` - przy przekazaniu URL do
        // Firefoksa `#` bywa kodowany do `%23` i strona się nie otwiera. Samo
        // `about:debugging` domyślnie pokazuje kartę „This Firefox".
        if let firefox = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.mozilla.firefox"),
           let debugURL = URL(string: "about:debugging") {
            NSWorkspace.shared.open([debugURL], withApplicationAt: firefox,
                                    configuration: NSWorkspace.OpenConfiguration())
        }
    }


    // MARK: - Przełączniki modułów

    var appBlockingEnabled: Bool { state.configuration.appBlockingEnabled }
    var websiteBlockingEnabled: Bool { state.configuration.websiteBlockingEnabled }

    /// Włącza/wyłącza cały moduł blokowania aplikacji. Wyłączenie osłabia ochronę → auth.
    func setAppBlockingEnabled(_ enabled: Bool) {
        if enabled {
            Task { await service.setAppBlockingEnabled(true) }
        } else {
            Task { if await authorize(.weakenSecuritySettings) { await service.setAppBlockingEnabled(false) } }
        }
    }

    /// Włącza/wyłącza moduł blokowania stron. Włączenie zakłada systemowe proxy
    /// (jednorazowy admin); wyłączenie je zdejmuje. Wyłączenie osłabia ochronę → auth.
    func setWebsiteBlockingEnabled(_ enabled: Bool) {
        if enabled {
            Task { await service.setWebsiteBlockingEnabled(true) }
        } else {
            Task { if await authorize(.weakenSecuritySettings) { await service.setWebsiteBlockingEnabled(false) } }
        }
    }

    func lock(_ app: ProtectedApp, reason: ActivityEvent.Reason = .userAction) {
        Task { await service.lock(appID: app.id, reason: reason) }
    }

    func lockAll() {
        Task { await service.lockAll(reason: .userAction) }
    }

    // MARK: - Blokada po odejściu (Bluetooth proximity)

    var proximityConfig: ProximityConfig { state.configuration.proximity }

    /// Zapis konfiguracji proximity przez seam (jak pozostałe ustawienia).
    func setProximityConfig(_ transform: (inout ProximityConfig) -> Void) {
        var config = state.configuration
        transform(&config.proximity)
        Task { await service.updateConfiguration(config) }
    }

    /// Blokada chronionych apek/stron wywołana oddaleniem urządzenia (powód „proximity").
    func lockAllForProximity() {
        Task { await service.lockAll(reason: .proximity) }
    }

    /// FAZA 1: zaślepka odblokowania (bez realnego Touch ID - Faza 5).
    func simulateUnlock(_ app: ProtectedApp) {
        Task { await service.markUnlocked(appID: app.id) }
    }

    func clearActivity() {
        Task { await service.clearActivityHistory() }
    }

    // MARK: - Przepływ uwierzytelnienia (Faza 1: okno + zaślepka; Faza 5: LocalAuthentication)

    /// Źródłem prawdy o żądaniu auth jest enforcement (stan), nie UI - dzięki temu
    /// automatyczne żądanie (po aktywacji zablokowanej apki) i ręczne „Unlock"
    /// działają tak samo.
    var pendingAuthSnapshot: ProtectedAppSnapshot? {
        guard let id = state.pendingAuthAppID else { return nil }
        return state.apps.first { $0.id == id }
    }

    func requestAuthentication(for app: ProtectedApp) {
        Task { await service.beginAuthentication(appID: app.id) }
    }

    func completeAuthentication(for app: ProtectedApp) {
        // Touch ID (z opcją hasła, jeśli apka na to pozwala); odblokowuje po sukcesie.
        Task { await service.authenticate(appID: app.id, preferPassword: false) }
    }

    /// „Use Password" - wymusza systemowy prompt z opcją hasła Maca.
    func usePassword(for app: ProtectedApp) {
        Task { await service.authenticate(appID: app.id, preferPassword: true) }
    }

    func cancelAuthentication(for app: ProtectedApp) {
        Task { await service.cancelAuthentication(appID: app.id) }
    }
}
