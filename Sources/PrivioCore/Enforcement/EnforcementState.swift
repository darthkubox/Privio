import Foundation

/// Migawka pojedynczej apki wysyłana przez seam do UI: konfiguracja + ulotny status.
/// Codable/Sendable, bez referencji do obiektów AppKit - gotowe pod transport XPC.
public struct ProtectedAppSnapshot: Identifiable, Codable, Hashable, Sendable {
    public var app: ProtectedApp
    public var status: LockStatus

    public var id: UUID { app.id }

    public init(app: ProtectedApp, status: LockStatus) {
        self.app = app
        self.status = status
    }

    /// Efektywny status z uwzględnieniem globalnego wyłącznika i flagi apki.
    public static func effectiveStatus(
        app: ProtectedApp,
        rawStatus: LockStatus,
        protectionActive: Bool
    ) -> LockStatus {
        guard protectionActive, app.protectionEnabled else { return .unprotected }
        return rawStatus
    }
}

/// Migawka chronionej strony WWW (Pro) wysyłana przez seam - analogicznie do apki.
public struct WebTargetSnapshot: Identifiable, Codable, Hashable, Sendable {
    public var target: WebTarget
    public var status: LockStatus

    public var id: UUID { target.id }

    public init(target: WebTarget, status: LockStatus) {
        self.target = target
        self.status = status
    }

    public static func effectiveStatus(
        target: WebTarget,
        rawStatus: LockStatus,
        protectionActive: Bool
    ) -> LockStatus {
        guard protectionActive, target.protectionEnabled else { return .unprotected }
        return rawStatus
    }
}

/// Żądanie wstrzymania ochrony stron zainicjowane z rozszerzenia. `minutes` niesie
/// wybraną długość; `id` odróżnia kolejne żądania (deduplikacja w `AppModel`).
public struct PauseRequest: Codable, Hashable, Sendable {
    public var id: UUID
    public var minutes: Int
    public init(id: UUID = UUID(), minutes: Int) { self.id = id; self.minutes = minutes }
}

/// Żądanie usunięcia strony z ochrony, pochodzące z rozszerzenia. Sama obecność
/// żądania niczego nie zmienia - `AppModel` najpierw wymaga Touch ID/hasła.
public struct WebRemovalRequest: Codable, Hashable, Sendable {
    public var id: UUID
    public var domain: String
    public init(id: UUID = UUID(), domain: String) { self.id = id; self.domain = domain }
}

/// Pełna migawka stanu enforcement przekazywana do UI (i menu bar).
/// To jedyny „widok" na enforcement, jaki dostaje warstwa prezentacji.
public struct EnforcementState: Codable, Hashable, Sendable {
    /// Globalny wyłącznik „Privio is Active".
    public var protectionActive: Bool
    public var apps: [ProtectedAppSnapshot]
    /// Chronione strony WWW (Pro) - blokada przez `/etc/hosts`.
    public var webTargets: [WebTargetSnapshot]
    public var configuration: AppConfiguration
    public var recentActivity: [ActivityEvent]
    /// Apka, dla której enforcement żąda uwierzytelnienia (steruje oknem auth).
    /// Ustawiane przez enforcement (np. po aktywacji zablokowanej apki) i przez
    /// akcję użytkownika „Unlock". UI tylko to odczytuje.
    public var pendingAuthAppID: UUID?
    /// Strona WWW, dla której trwa żądanie uwierzytelnienia (przycisk „Unlock").
    public var pendingAuthWebID: UUID?
    /// Nonce żądania otwarcia panelu Privio z rozszerzenia (przycisk „Otwórz
    /// ustawienia"). Zmiana wartości → UI podnosi okno (za bramką Touch ID).
    /// Runtime‑only: transportowany przez seam, ale nigdy nie persystowany.
    public var panelOpenRequest: UUID?
    /// Do kiedy ochrona stron jest wstrzymana (snooze z rozszerzenia). nil = nie.
    /// Runtime‑only: nie persystujemy (restart = wznowienie - wzmacnia ochronę).
    public var webPauseUntil: Date?
    /// Żądanie wstrzymania z rozszerzenia (nonce + minuty) - `AppModel` bramkuje je
    /// Touch ID, po czym woła `pauseWebsiteProtection`. Runtime‑only.
    public var pendingPauseRequest: PauseRequest?
    public var pendingWebRemovalRequest: WebRemovalRequest?
    /// Czy integralność zapisanej konfiguracji (HMAC) jest poprawna (sekcja 13).
    public var configIntegrityValid: Bool

    public init(
        protectionActive: Bool = true,
        apps: [ProtectedAppSnapshot] = [],
        webTargets: [WebTargetSnapshot] = [],
        configuration: AppConfiguration = .default,
        recentActivity: [ActivityEvent] = [],
        pendingAuthAppID: UUID? = nil,
        pendingAuthWebID: UUID? = nil,
        panelOpenRequest: UUID? = nil,
        webPauseUntil: Date? = nil,
        pendingPauseRequest: PauseRequest? = nil,
        pendingWebRemovalRequest: WebRemovalRequest? = nil,
        configIntegrityValid: Bool = true
    ) {
        self.protectionActive = protectionActive
        self.apps = apps
        self.webTargets = webTargets
        self.configuration = configuration
        self.recentActivity = recentActivity
        self.pendingAuthAppID = pendingAuthAppID
        self.pendingAuthWebID = pendingAuthWebID
        self.panelOpenRequest = panelOpenRequest
        self.webPauseUntil = webPauseUntil
        self.pendingPauseRequest = pendingPauseRequest
        self.pendingWebRemovalRequest = pendingWebRemovalRequest
        self.configIntegrityValid = configIntegrityValid
    }

    // Dekodowanie wstecznie zgodne: starsze migawki bez pól web → puste/nil.
    private enum CodingKeys: String, CodingKey {
        case protectionActive, apps, webTargets, configuration, recentActivity
        case pendingAuthAppID, pendingAuthWebID, panelOpenRequest
        case webPauseUntil, pendingPauseRequest, pendingWebRemovalRequest, configIntegrityValid
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        protectionActive = try c.decodeIfPresent(Bool.self, forKey: .protectionActive) ?? true
        apps = try c.decodeIfPresent([ProtectedAppSnapshot].self, forKey: .apps) ?? []
        webTargets = try c.decodeIfPresent([WebTargetSnapshot].self, forKey: .webTargets) ?? []
        configuration = try c.decodeIfPresent(AppConfiguration.self, forKey: .configuration) ?? .default
        recentActivity = try c.decodeIfPresent([ActivityEvent].self, forKey: .recentActivity) ?? []
        pendingAuthAppID = try c.decodeIfPresent(UUID.self, forKey: .pendingAuthAppID)
        pendingAuthWebID = try c.decodeIfPresent(UUID.self, forKey: .pendingAuthWebID)
        panelOpenRequest = try c.decodeIfPresent(UUID.self, forKey: .panelOpenRequest)
        webPauseUntil = try c.decodeIfPresent(Date.self, forKey: .webPauseUntil)
        pendingPauseRequest = try c.decodeIfPresent(PauseRequest.self, forKey: .pendingPauseRequest)
        pendingWebRemovalRequest = try c.decodeIfPresent(WebRemovalRequest.self, forKey: .pendingWebRemovalRequest)
        configIntegrityValid = try c.decodeIfPresent(Bool.self, forKey: .configIntegrityValid) ?? true
    }

    /// Czy ochrona stron jest teraz wstrzymana (snooze jeszcze trwa).
    public var isWebProtectionPaused: Bool {
        if let until = webPauseUntil { return until > Date() }
        return false
    }

    public func snapshot(for id: UUID) -> ProtectedAppSnapshot? {
        apps.first { $0.id == id }
    }

    /// Liczba apek aktualnie zablokowanych (do znaczka w menu bar / About).
    public var lockedCount: Int {
        apps.filter { $0.status == .locked }.count
    }

    /// Buduje stan startowy z persystencji. Po starcie wszystko jest zablokowane
    /// (żadnego trwałego „unlocked"). Współdzielone przez UI (render startowy)
    /// i enforcement.
    public static func loaded(from store: ConfigStore) -> EnforcementState {
        let persisted = store.load()
        let apps = persisted.apps
            .map { ProtectedAppSnapshot(app: $0, status: $0.protectionEnabled ? .locked : .unprotected) }
            .sorted { $0.app.displayName.localizedCaseInsensitiveCompare($1.app.displayName) == .orderedAscending }
        let webTargets = persisted.webTargets
            .map { WebTargetSnapshot(target: $0, status: $0.protectionEnabled ? .locked : .unprotected) }
            .sorted { $0.target.displayName.localizedCaseInsensitiveCompare($1.target.displayName) == .orderedAscending }
        return EnforcementState(
            protectionActive: persisted.configuration.protectionActive,
            apps: apps,
            webTargets: webTargets,
            configuration: persisted.configuration,
            recentActivity: [])
    }
}
