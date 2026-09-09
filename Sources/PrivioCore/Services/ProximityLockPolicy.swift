import Foundation

/// Pojedynczy odczyt zaufanego urządzenia dostarczany przez monitor Bluetooth.
/// `rssi`/`batteryPercent` mogą być `nil`, gdy system ich nie udostępnia - polityka
/// degraduje się wtedy bezpiecznie do samego stanu połączenia.
public struct ProximityDeviceReading: Sendable, Hashable {
    public let deviceID: String
    public let isConnected: Bool
    public let rssi: Int?
    public let batteryPercent: Int?

    public init(deviceID: String, isConnected: Bool, rssi: Int? = nil, batteryPercent: Int? = nil) {
        self.deviceID = deviceID
        self.isConnected = isConnected
        self.rssi = rssi
        self.batteryPercent = batteryPercent
    }
}

/// Decyzja polityki dla pojedynczego „tiknięcia".
public enum ProximityDecision: Equatable, Sendable {
    /// Nic - brak akcji.
    case none
    /// Zablokuj wskazany cel (edge-trigger: obecny → nieobecny, po debounce/karencji).
    case lock(ProximityLockTarget)
    /// Bezpiecznik: zbyt wiele blokad w krótkim oknie ⇒ moduł sam się wstrzymał.
    case autoPaused
}

/// Czysta, w pełni testowalna maszyna stanów decydująca, KIEDY zablokować po
/// odejściu. Nie dotyka Bluetooth, ekranu ani enforcementu - dostaje odczyty i
/// czas, zwraca decyzję. Tu żyją wszystkie gwarancje anty-lockout (Post-MVP §3):
///
/// 1. Nieobecność „w spoczynku" nie blokuje - blokada tylko na krawędzi *obecny → nieobecny*.
/// 2. Obecność nigdy nie jest warunkiem odblokowania (to zapewnia reszta systemu).
/// 3. Re-uzbrojenie dopiero po ponownej obserwacji obecności (po blokadzie DISARM).
/// 4. Karencja po każdym odblokowaniu (`noteUnlock`) - nie blokuje od razu.
/// 5. Debounce „oddalenia" - away musi utrzymać się `awayDebounceSeconds`.
/// 6. Bezpiecznik - kilka blokad w oknie ⇒ auto-pauza.
/// 7. Niska bateria zaufanego urządzenia ⇒ wstrzymanie blokowania.
/// 8. Wyłącznik (`config.paused`) / `resume()` zawsze pod ręką.
public struct ProximityLockPolicy: Sendable {
    /// Okno i limit bezpiecznika (migotanie RSSI/połączenia).
    public static let circuitWindowSeconds: TimeInterval = 120
    public static let circuitMaxLocks = 3

    // Stan wewnętrzny (ephemeryczny - nigdy nie utrwalany).
    private var armed = false
    private var awaySince: Date?
    private var graceUntil: Date?
    private var recentLocks: [Date] = []
    private var autoPaused = false
    /// Ostatnia znana bateria per urządzenie - bo w chwili rozłączenia/odejścia odczyt
    /// baterii znika, a właśnie *padające* urządzenie wygląda wtedy jak „oddalone".
    private var lastKnownBattery: [String: Int] = [:]
    /// Urządzenia, które kiedykolwiek podały RSSI (mierzą odległość, np. beacon zegarka).
    /// Klasyfikacja musi przetrwać moment nieobecności (gdy odczyt RSSI znika), dlatego
    /// zapamiętujemy ją, a nie liczymy z bieżącego odczytu.
    private var rssiCapable: Set<String> = []

    public init() {}

    public var isArmed: Bool { armed }
    public var isAutoPaused: Bool { autoPaused }

    /// Urządzenie jest „obecne", gdy jest połączone i - jeśli znamy RSSI - nie słabsze
    /// niż próg. Brak RSSI ⇒ ufamy samemu połączeniu.
    private func isPresent(_ reading: ProximityDeviceReading?, threshold: Int) -> Bool {
        guard let reading, reading.isConnected else { return false }
        if let rssi = reading.rssi { return rssi >= threshold }
        return true
    }

    /// Startuje karencję po odblokowaniu i rozbraja politykę - kolejna blokada wymaga
    /// ponownego zobaczenia urządzenia jako obecnego (warstwy 3 i 4).
    public mutating func noteUnlock(at now: Date, config: ProximityConfig) {
        graceUntil = now.addingTimeInterval(Double(config.graceAfterUnlockSeconds))
        armed = false
        awaySince = nil
    }

    /// Ręczne wznowienie po auto-pauzie bezpiecznika (warstwa 8). Rozbraja, żeby nie
    /// zablokować natychmiast po wznowieniu.
    public mutating func resume() {
        autoPaused = false
        armed = false
        awaySince = nil
        recentLocks.removeAll()
    }

    /// Ocenia jeden „tik". Wywoływane cyklicznie i/lub przy każdej zmianie odczytów.
    public mutating func evaluate(readings: [ProximityDeviceReading],
                                  config: ProximityConfig,
                                  at now: Date) -> ProximityDecision {
        // Tylko aktywne (nie wyłączone przez użytkownika) urządzenia biorą udział w blokowaniu.
        let active = config.activeTrustedDeviceIDs
        // Warstwa 8 / stany wyłączające: rozbrój, aby wznowienie wymagało ponownej obecności.
        guard config.enabled, !config.paused, !autoPaused, !active.isEmpty else {
            armed = false
            awaySince = nil
            return .none
        }

        let byID = Dictionary(readings.map { ($0.deviceID, $0) }, uniquingKeysWith: { _, last in last })
        for (id, reading) in byID {
            if let battery = reading.batteryPercent { lastKnownBattery[id] = battery }
            if reading.rssi != nil { rssiCapable.insert(id) }
        }
        // Urządzenia mierzące odległość (RSSI, np. beacon zegarka) napędzają decyzję: jeśli
        // takie są wśród aktywnych, to one decydują o obecności. Urządzenia bez sygnału
        // (słuchawki), których samo rozłączenie może znaczyć „schowane do etui", nie blokują
        // wtedy samodzielnie. Gdy masz tylko urządzenia bez RSSI - decyduje ich połączenie.
        let capable = active.filter { rssiCapable.contains($0) }
        let deciding = capable.isEmpty ? active : capable
        // Obecny, gdy KTÓREKOLWIEK urządzenie dystansowe jest w zasięgu; blokuj dopiero
        // gdy odeszły WSZYSTKIE. Odporne na chwilowe zniknięcie jednego z kilku beaconów
        // (dla jednego urządzenia `contains` == `allSatisfy`).
        let present = deciding.contains { isPresent(byID[$0], threshold: config.rssiThreshold) }

        if present {
            armed = true          // warstwa 3: obserwacja obecności uzbraja
            awaySince = nil
            return .none
        }

        // Nieobecny.
        guard armed else { return .none }            // warstwa 1: nieobecność w spoczynku nie blokuje
        if awaySince == nil { awaySince = now }       // start debounce (warstwa 5)

        // Warstwa 4: karencja po odblokowaniu - nie blokuj, ale pozwól debounce'owi biec.
        if let grace = graceUntil, now < grace { return .none }

        // Warstwa 7: niska bateria któregokolwiek zaufanego urządzenia (wg ostatniego
        // znanego odczytu) wstrzymuje blokowanie. Bateria nieznana ⇒ nie wstrzymuje.
        let lowBattery = active.contains { id in
            if let battery = lastKnownBattery[id] { return battery < config.lowBatteryThreshold }
            return false
        }
        if lowBattery { return .none }

        // Warstwa 5: „oddalony" musi utrzymać się wymagany czas.
        guard let awaySince, now.timeIntervalSince(awaySince) >= Double(config.awayDebounceSeconds) else {
            return .none
        }

        // Wyzwolenie blokady.
        armed = false                                 // warstwa 3: DISARM do ponownej obecności
        self.awaySince = nil
        recentLocks.append(now)
        recentLocks.removeAll { now.timeIntervalSince($0) > Self.circuitWindowSeconds }
        if recentLocks.count >= Self.circuitMaxLocks { // warstwa 6: bezpiecznik
            autoPaused = true
            return .autoPaused
        }
        return .lock(config.lockTarget)
    }
}
