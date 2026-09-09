import Foundation

/// Wariant wizualny Zasłony prywatności (Privacy Curtain).
public enum PrivacyCurtainMode: String, Codable, Sendable, CaseIterable {
    /// Rozmycie systemowe treści.
    case blur
    /// Mocne przyciemnienie + „latarka" wokół kursora.
    case spotlight
    /// Przyciemnienie + obniżony kontrast/tint utrudniający podglądanie z boku.
    case tint
}

/// Zakres działania Zasłony prywatności.
public enum PrivacyCurtainScope: String, Codable, Sendable, CaseIterable {
    /// Tylko gdy na wierzchu jest aplikacja chroniona Touch ID/hasłem.
    case protectedApps
    /// Cały ekran, niezależnie od aktywnej aplikacji.
    case fullScreen
}

/// Kształt „latarki" w trybie spotlight.
public enum PrivacyCurtainSpotlightShape: String, Codable, Sendable, CaseIterable {
    case circle
    case ellipse
    case rectangle
}

/// Globalne ustawienia Privio (sekcja 20). Utrwalane obok listy chronionych apek.
public struct AppConfiguration: Codable, Hashable, Sendable {
    // General
    public var startAtLogin: Bool
    public var showMenuBarIcon: Bool
    public var lockAllAfterScreenLock: Bool
    public var lockAllAfterSleep: Bool

    // Security (domyślne wartości dla nowo dodanych apek)
    public var defaultRequireTouchID: Bool
    public var defaultAllowPasswordFallback: Bool
    public var defaultLockTimeout: TimeInterval?   // nil = never
    public var defaultQuitTimeout: TimeInterval?   // nil = never
    /// Jawnie włączana funkcja: lokalne zdjęcie po faktycznie błędnym auth.
    public var captureFailedAttempts: Bool

    /// Globalny wyłącznik ochrony („Privio is Active"). Wyłączenie wymaga
    /// uwierzytelnienia (sekcja 18) - samo pole trzyma tylko intencję.
    public var protectionActive: Bool
    /// Niezależny, sytuacyjny moduł Zasłony prywatności (blur/spotlight/tint).
    public var privacyModeEnabled: Bool
    /// Globalny skrót przełączający Zasłonę prywatności. nil = wyłączony.
    public var privacyModeShortcut: String?
    /// Kombinacja modyfikatorów trzymana, aby chwilowo odsłonić zasłonę.
    public var privacyRevealHoldShortcut: String
    /// Globalny skrót blokujący/odblokowujący odsłonięcie.
    public var privacyRevealLockShortcut: String?
    /// Wariant wizualny Zasłony prywatności.
    public var privacyCurtainMode: PrivacyCurtainMode
    /// Zakres: cały ekran czy tylko chronione aplikacje.
    public var privacyCurtainScope: PrivacyCurtainScope
    /// Siła przyciemnienia (0.5-0.98).
    public var privacyCurtainIntensity: Double
    /// Promień „latarki" w punktach (tryb spotlight).
    public var privacyCurtainSpotlightRadius: Double
    /// Kształt „latarki" (tryb spotlight).
    public var privacyCurtainSpotlightShape: PrivacyCurtainSpotlightShape

    /// Moduł blokowania APLIKACJI - można go całkiem wyłączyć (wtedy żadne apki nie
    /// są chronione, niezależnie od per‑app). Domyślnie włączony.
    public var appBlockingEnabled: Bool
    /// Moduł blokowania STRON - jego włączenie zakłada systemowe proxy (jednorazowy
    /// admin), wyłączenie je zdejmuje. Opt‑in (zmienia ustawienia sieci), domyślnie OFF.
    public var websiteBlockingEnabled: Bool

    /// Moduł „Blokada po odejściu" (Bluetooth proximity, Pro). Domyślnie wyłączony.
    public var proximity: ProximityConfig

    public init(
        startAtLogin: Bool = false,
        showMenuBarIcon: Bool = true,
        lockAllAfterScreenLock: Bool = true,
        lockAllAfterSleep: Bool = true,
        defaultRequireTouchID: Bool = true,
        defaultAllowPasswordFallback: Bool = true,   // domyślnie: Touch ID lub hasło Maca
        defaultLockTimeout: TimeInterval? = 120,
        defaultQuitTimeout: TimeInterval? = nil,
        captureFailedAttempts: Bool = false,
        protectionActive: Bool = true,
        privacyModeEnabled: Bool = false,
        privacyModeShortcut: String? = "option-command-l",
        privacyRevealHoldShortcut: String = "option-command",
        privacyRevealLockShortcut: String? = "option-command-p",
        privacyCurtainMode: PrivacyCurtainMode = .blur,
        privacyCurtainScope: PrivacyCurtainScope = .protectedApps,
        privacyCurtainIntensity: Double = 0.85,
        privacyCurtainSpotlightRadius: Double = 180,
        privacyCurtainSpotlightShape: PrivacyCurtainSpotlightShape = .circle,
        appBlockingEnabled: Bool = true,
        websiteBlockingEnabled: Bool = false,
        proximity: ProximityConfig = ProximityConfig()
    ) {
        self.startAtLogin = startAtLogin
        self.showMenuBarIcon = showMenuBarIcon
        self.lockAllAfterScreenLock = lockAllAfterScreenLock
        self.lockAllAfterSleep = lockAllAfterSleep
        self.defaultRequireTouchID = defaultRequireTouchID
        self.defaultAllowPasswordFallback = defaultAllowPasswordFallback
        self.defaultLockTimeout = defaultLockTimeout
        self.defaultQuitTimeout = defaultQuitTimeout
        self.captureFailedAttempts = captureFailedAttempts
        self.protectionActive = protectionActive
        self.privacyModeEnabled = privacyModeEnabled
        self.privacyModeShortcut = privacyModeShortcut
        self.privacyRevealHoldShortcut = privacyRevealHoldShortcut
        self.privacyRevealLockShortcut = privacyRevealLockShortcut
        self.privacyCurtainMode = privacyCurtainMode
        self.privacyCurtainScope = privacyCurtainScope
        self.privacyCurtainIntensity = privacyCurtainIntensity
        self.privacyCurtainSpotlightRadius = privacyCurtainSpotlightRadius
        self.privacyCurtainSpotlightShape = privacyCurtainSpotlightShape
        self.appBlockingEnabled = appBlockingEnabled
        self.websiteBlockingEnabled = websiteBlockingEnabled
        self.proximity = proximity
    }

    private enum CodingKeys: String, CodingKey {
        case startAtLogin, showMenuBarIcon, lockAllAfterScreenLock, lockAllAfterSleep
        case defaultRequireTouchID, defaultAllowPasswordFallback
        case defaultLockTimeout, defaultQuitTimeout, captureFailedAttempts, protectionActive
        case privacyModeEnabled, privacyModeShortcut, privacyRevealHoldShortcut, privacyRevealLockShortcut
        case privacyCurtainMode, privacyCurtainScope, privacyCurtainIntensity
        case privacyCurtainSpotlightRadius, privacyCurtainSpotlightShape
        case appBlockingEnabled, websiteBlockingEnabled
        case proximity
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        startAtLogin = try values.decodeIfPresent(Bool.self, forKey: .startAtLogin) ?? false
        showMenuBarIcon = try values.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        lockAllAfterScreenLock = try values.decodeIfPresent(Bool.self, forKey: .lockAllAfterScreenLock) ?? true
        lockAllAfterSleep = try values.decodeIfPresent(Bool.self, forKey: .lockAllAfterSleep) ?? true
        defaultRequireTouchID = try values.decodeIfPresent(Bool.self, forKey: .defaultRequireTouchID) ?? true
        defaultAllowPasswordFallback = try values.decodeIfPresent(Bool.self, forKey: .defaultAllowPasswordFallback) ?? true
        defaultLockTimeout = values.contains(.defaultLockTimeout)
            ? try values.decodeIfPresent(TimeInterval.self, forKey: .defaultLockTimeout)
            : 120
        defaultQuitTimeout = try values.decodeIfPresent(TimeInterval.self, forKey: .defaultQuitTimeout)
        captureFailedAttempts = try values.decodeIfPresent(Bool.self, forKey: .captureFailedAttempts) ?? false
        protectionActive = try values.decodeIfPresent(Bool.self, forKey: .protectionActive) ?? true
        privacyModeEnabled = try values.decodeIfPresent(Bool.self, forKey: .privacyModeEnabled) ?? false
        privacyModeShortcut = values.contains(.privacyModeShortcut)
            ? try values.decodeIfPresent(String.self, forKey: .privacyModeShortcut)
            : "option-command-l"
        privacyRevealHoldShortcut = try values.decodeIfPresent(String.self, forKey: .privacyRevealHoldShortcut)
            ?? "option-command"
        privacyRevealLockShortcut = values.contains(.privacyRevealLockShortcut)
            ? try values.decodeIfPresent(String.self, forKey: .privacyRevealLockShortcut)
            : "option-command-p"
        privacyCurtainMode = (try? values.decode(PrivacyCurtainMode.self, forKey: .privacyCurtainMode)) ?? .blur
        privacyCurtainScope = (try? values.decode(PrivacyCurtainScope.self, forKey: .privacyCurtainScope)) ?? .protectedApps
        privacyCurtainIntensity = ((try? values.decode(Double.self, forKey: .privacyCurtainIntensity)) ?? 0.85)
            .clampedCurtainIntensity()
        privacyCurtainSpotlightRadius = ((try? values.decode(Double.self, forKey: .privacyCurtainSpotlightRadius)) ?? 180)
            .clampedSpotlightRadius()
        privacyCurtainSpotlightShape = (try? values.decode(PrivacyCurtainSpotlightShape.self, forKey: .privacyCurtainSpotlightShape)) ?? .circle
        appBlockingEnabled = try values.decodeIfPresent(Bool.self, forKey: .appBlockingEnabled) ?? true
        websiteBlockingEnabled = try values.decodeIfPresent(Bool.self, forKey: .websiteBlockingEnabled) ?? false
        proximity = (try? values.decodeIfPresent(ProximityConfig.self, forKey: .proximity)) ?? ProximityConfig()
    }

    public static let `default` = AppConfiguration()

    /// Dozwolone zakresy regulowanych parametrów Zasłony prywatności (wspólne dla UI i kontrolera).
    public static let curtainIntensityRange: ClosedRange<Double> = 0.5...0.98
    public static let spotlightRadiusRange: ClosedRange<Double> = 60...500
}

public extension Double {
    func clampedCurtainIntensity() -> Double {
        Swift.min(Swift.max(self, AppConfiguration.curtainIntensityRange.lowerBound),
                  AppConfiguration.curtainIntensityRange.upperBound)
    }

    func clampedSpotlightRadius() -> Double {
        Swift.min(Swift.max(self, AppConfiguration.spotlightRadiusRange.lowerBound),
                  AppConfiguration.spotlightRadiusRange.upperBound)
    }
}
