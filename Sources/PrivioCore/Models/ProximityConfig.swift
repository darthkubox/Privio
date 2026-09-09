import Foundation

/// Co blokuje „Blokada po odejściu" po zniknięciu zaufanego urządzenia.
public enum ProximityLockTarget: String, Codable, Sendable, CaseIterable {
    /// Cały ekran / system (wygaszacz + „wymagaj hasła natychmiast"). Najmocniejsze,
    /// ale zależne od ustawień systemowych (patrz Post-MVP: ograniczenia macOS).
    case screen
    /// Tylko chronione aplikacje/strony/sejf Privio - w pełni natywne, bez zależności.
    case protectedApps
}

/// Konfiguracja modułu „Blokada po odejściu" (Bluetooth proximity auto-lock, Pro).
///
/// Trzyma wyłącznie intencje i **stabilne identyfikatory sparowanych urządzeń** -
/// żadnych sekretów, zgodnie z zasadą „`PersistedState` bez sekretów". Wszystkie
/// pola dekodowane defensywnie, aby starszy `config.json` działał dalej.
///
/// Nadrzędna zasada bezpieczeństwa: urządzenie jest **wyłącznie wyzwalaczem
/// zablokowania przy odejściu**, nigdy warunkiem odblokowania. Logika decyzyjna
/// (edge-trigger, debounce, karencja, re-uzbrojenie, bezpiecznik, niska bateria)
/// żyje w `ProximityLockPolicy` i jest w pełni pokryta testami.
public struct ProximityConfig: Codable, Hashable, Sendable {
    public var enabled: Bool
    /// Zaufane urządzenia (do `maxTrustedDevices`). Zostają na liście nawet gdy wyłączone.
    public var trustedDeviceIDs: [String]
    /// Urządzenia z listy tymczasowo **wyłączone z blokowania** (jak wyłączona apka/strona) -
    /// nie są usuwane, po prostu nie liczą się do decyzji, dopóki użytkownik ich nie włączy.
    public var disabledDeviceIDs: [String]
    public var lockTarget: ProximityLockTarget
    /// „Oddalony" musi utrzymać się tyle sekund, zanim uznamy odejście (histereza/debounce).
    public var awayDebounceSeconds: Int
    /// Karencja po każdym odblokowaniu, zanim blokada po odejściu znów zadziała (~60 s).
    public var graceAfterUnlockSeconds: Int
    /// Próg RSSI (dBm, ujemny) poniżej którego urządzenie liczymy jako „oddalone".
    public var rssiThreshold: Int
    /// Próg baterii (%) zaufanego urządzenia, poniżej którego blokowanie jest **wstrzymane**
    /// (żeby padające urządzenie nie zablokowało Cię tuż przed śmiercią). Nigdy nie zdejmuje blokad.
    public var lowBatteryThreshold: Int
    /// Ręczny wyłącznik (pasek menu / Ustawienia) - wstrzymuje bez utraty konfiguracji.
    public var paused: Bool

    public init(
        enabled: Bool = false,
        trustedDeviceIDs: [String] = [],
        disabledDeviceIDs: [String] = [],
        lockTarget: ProximityLockTarget = .screen,
        awayDebounceSeconds: Int = 15,
        graceAfterUnlockSeconds: Int = 60,
        rssiThreshold: Int = -75,
        lowBatteryThreshold: Int = 15,
        paused: Bool = false
    ) {
        self.enabled = enabled
        let trusted = Array(trustedDeviceIDs.prefix(Self.maxTrustedDevices))
        self.trustedDeviceIDs = trusted
        // Trzymaj tylko wyłączenia dotyczące urządzeń faktycznie na liście.
        self.disabledDeviceIDs = disabledDeviceIDs.filter { trusted.contains($0) }
        self.lockTarget = lockTarget
        self.awayDebounceSeconds = awayDebounceSeconds.clamped(to: Self.awayDebounceRange)
        self.graceAfterUnlockSeconds = graceAfterUnlockSeconds.clamped(to: Self.graceRange)
        self.rssiThreshold = rssiThreshold.clamped(to: Self.rssiThresholdRange)
        self.lowBatteryThreshold = lowBatteryThreshold.clamped(to: Self.lowBatteryRange)
        self.paused = paused
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, trustedDeviceIDs, disabledDeviceIDs, lockTarget, awayDebounceSeconds
        case graceAfterUnlockSeconds, rssiThreshold, lowBatteryThreshold, paused
    }

    public init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ProximityConfig()
        self.init(
            enabled: (try? v.decodeIfPresent(Bool.self, forKey: .enabled)) ?? defaults.enabled,
            trustedDeviceIDs: (try? v.decodeIfPresent([String].self, forKey: .trustedDeviceIDs)) ?? defaults.trustedDeviceIDs,
            disabledDeviceIDs: (try? v.decodeIfPresent([String].self, forKey: .disabledDeviceIDs)) ?? defaults.disabledDeviceIDs,
            lockTarget: (try? v.decode(ProximityLockTarget.self, forKey: .lockTarget)) ?? defaults.lockTarget,
            awayDebounceSeconds: (try? v.decodeIfPresent(Int.self, forKey: .awayDebounceSeconds)) ?? defaults.awayDebounceSeconds,
            graceAfterUnlockSeconds: (try? v.decodeIfPresent(Int.self, forKey: .graceAfterUnlockSeconds)) ?? defaults.graceAfterUnlockSeconds,
            rssiThreshold: (try? v.decodeIfPresent(Int.self, forKey: .rssiThreshold)) ?? defaults.rssiThreshold,
            lowBatteryThreshold: (try? v.decodeIfPresent(Int.self, forKey: .lowBatteryThreshold)) ?? defaults.lowBatteryThreshold,
            paused: (try? v.decodeIfPresent(Bool.self, forKey: .paused)) ?? defaults.paused
        )
    }

    /// Zaufane urządzenia, które NIE są wyłączone - tylko te napędzają decyzję policy.
    public var activeTrustedDeviceIDs: [String] {
        trustedDeviceIDs.filter { !disabledDeviceIDs.contains($0) }
    }

    /// Czy dane urządzenie z listy jest aktywne (bierze udział w blokowaniu).
    public func isDeviceActive(_ id: String) -> Bool {
        trustedDeviceIDs.contains(id) && !disabledDeviceIDs.contains(id)
    }

    public static let maxTrustedDevices = 5
    public static let awayDebounceRange: ClosedRange<Int> = 5...120
    public static let graceRange: ClosedRange<Int> = 15...300
    public static let rssiThresholdRange: ClosedRange<Int> = -95 ... -40
    public static let lowBatteryRange: ClosedRange<Int> = 5...50
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
