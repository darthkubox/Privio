import CoreBluetooth
import Foundation
import Observation
import PrivioCore

/// Koordynator modułu „Blokada po odejściu": spina monitor Bluetooth
/// (`ProximityMonitoring`) z czystą maszyną stanów (`ProximityLockPolicy`) i wykonuje
/// decyzję. Żyje w warstwie aplikacji, bo cel „apki Privio" obejmuje też sejf, a cel
/// „ekran" dotyka systemu - obie rzeczy poza seamem enforcementu.
///
/// Bezpieczeństwo: kontroler NIGDY nie odblokowuje - jedynie na decyzję polityki
/// wywołuje blokadę. Odblokowanie to zawsze normalny auth macOS.
@MainActor
@Observable
final class ProximityController {
    private(set) var devices: [ProximityDeviceInfo] = []
    private(set) var knownDevices: [String: ProximityDeviceInfo] = [:]
    private(set) var config: ProximityConfig
    private(set) var bluetoothState: BluetoothRadioState = .unknown
    /// Ustawione, gdy bezpiecznik sam wstrzymał moduł (migotanie) - UI pokazuje komunikat.
    private(set) var autoPausedNotice = false

    @ObservationIgnored private let monitor: ProximityMonitoring
    @ObservationIgnored private let screenLock: ScreenLockControlling
    @ObservationIgnored private let events = WorkspaceSystemEventMonitor()
    @ObservationIgnored private var policy = ProximityLockPolicy()
    @ObservationIgnored private var deviceTask: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var monitorRunning = false
    @ObservationIgnored private var sectionVisible = false
    @ObservationIgnored private let isSnapshot: Bool

    /// Akcje wykonawcze wstrzykiwane przy montażu (dostęp do enforcementu/sejfu).
    var onLockProtectedApps: (@MainActor () -> Void)?
    var onLockVault: (@MainActor () -> Void)?
    /// Utrwala `paused` w konfiguracji (np. gdy bezpiecznik sam wstrzyma moduł).
    var onPersistPaused: (@MainActor (Bool) -> Void)?

    init(config: ProximityConfig = ProximityConfig(),
         monitor: ProximityMonitoring? = nil,
         screenLock: ScreenLockControlling? = nil,
         isSnapshot: Bool = false) {
        self.isSnapshot = isSnapshot
        self.config = config
        self.monitor = monitor ?? (isSnapshot
            ? ManualProximityMonitor(devices: Self.sampleDevices)
            : BluetoothProximityMonitor())
        self.screenLock = screenLock ?? (isSnapshot ? NoopScreenLock() : SystemScreenLock())
        if let bluetoothMonitor = self.monitor as? BluetoothProximityMonitor {
            bluetoothMonitor.onBluetoothState = { [weak self] state in
                Task { @MainActor [weak self] in self?.bluetoothState = state }
            }
            bluetoothMonitor.onRemoteLock = { [weak self] in
                Task { @MainActor [weak self] in self?.screenLock.lockScreen() }
            }
        }
    }

    var isConfigured: Bool { !config.trustedDeviceIDs.isEmpty }
    /// Wear OS watches generally keep only a momentary classic Bluetooth connection.
    /// That signal cannot safely represent presence; the user must select/associate BLE.
    var hasClassicWatchWithoutBLE: Bool {
        config.trustedDeviceIDs.contains { id in
            !id.hasPrefix("ble:") && deviceInfo(for: id).kind == .watch
        }
    }

    /// Stan menedżera ma pierwszeństwo, bo po zmianie podpisu lokalnego buildu
    /// `CBManager.authorization` może wyglądać poprawnie mimo faktycznej odmowy TCC.
    var bluetoothDenied: Bool {
        if bluetoothState == .unauthorized { return true }
        switch CBManager.authorization {
        case .denied, .restricted: return true
        default: return false
        }
    }

    func start() {
        if isSnapshot {
            devices = Self.sampleDevices
            knownDevices = Dictionary(uniqueKeysWithValues: Self.sampleDevices.map { ($0.id, $0) })
            return
        }
        guard !started else { return }
        started = true
        // Obserwacja odblokowania ekranu (bez Bluetooth) - startuje karencję (~60 s)
        // i nie zdejmuje żadnych blokad.
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.events.start() {
                if let bluetoothMonitor = self.monitor as? BluetoothProximityMonitor {
                    switch event {
                    case .screenLocked, .sessionResigned: bluetoothMonitor.updateMacLockState(true)
                    case .screenUnlocked, .sessionBecameActive: bluetoothMonitor.updateMacLockState(false)
                    default: break
                    }
                }
                if case .screenUnlocked = event {
                    self.policy.noteUnlock(at: Date(), config: self.config)
                }
            }
        }
        reconcileMonitor()
    }

    /// Sekcja proximity jest na ekranie - trzeba pokazać listę urządzeń, więc dostęp do
    /// Bluetooth (i systemowe pytanie o zgodę) uruchamia się dopiero teraz.
    func setSectionVisible(_ visible: Bool) {
        sectionVisible = visible
        reconcileMonitor()
    }

    /// Monitor Bluetooth działa TYLKO gdy moduł jest włączony albo gdy patrzysz na
    /// sekcję - nigdy „na zapas" przy każdym uruchomieniu apki (inaczej każdy użytkownik
    /// dostawałby pytanie o Bluetooth, a na macOS bez opisu uprawnienia - crash TCC).
    private func reconcileMonitor() {
        guard !isSnapshot else { return }
        let shouldRun = config.enabled || sectionVisible
        ProximityDiag.log("reconcile: shouldRun=\(shouldRun) running=\(monitorRunning) enabled=\(config.enabled) sectionVisible=\(sectionVisible) btDenied=\(bluetoothDenied)")
        if shouldRun, !monitorRunning {
            monitorRunning = true
            monitor.start()
            deviceTask = Task { [weak self] in
                guard let self else { return }
                for await list in self.monitor.deviceUpdates() {
                    self.devices = list
                    for device in list { self.knownDevices[device.id] = device }
                    self.evaluate()
                }
            }
        } else if !shouldRun, monitorRunning {
            monitorRunning = false
            deviceTask?.cancel()
            deviceTask = nil
            monitor.stop()
        }
    }

    /// Wołane z `AppModel` przy każdej migawce stanu. Zmiana zaufanych urządzeń,
    /// włącznika lub celu blokady resetuje politykę (świeży stan ⇒ wymaga ponownej
    /// obserwacji obecności - nie zablokuje tylko dlatego, że dodano nieobecne urządzenie).
    func update(config newConfig: ProximityConfig) {
        let old = config
        config = newConfig
        if newConfig.trustedDeviceIDs != old.trustedDeviceIDs
            || newConfig.disabledDeviceIDs != old.disabledDeviceIDs
            || newConfig.enabled != old.enabled
            || newConfig.lockTarget != old.lockTarget {
            policy = ProximityLockPolicy()
            autoPausedNotice = false
        }
        reconcileMonitor()
    }

    /// Ręczny wyłącznik (pasek menu / Ustawienia). Wznowienie rozbraja politykę,
    /// żeby nie zablokować od razu, i czyści komunikat bezpiecznika.
    func setPaused(_ paused: Bool) {
        if !paused {
            policy.resume()
            autoPausedNotice = false
        }
        onPersistPaused?(paused)
    }

    func isTrusted(_ id: String) -> Bool { config.trustedDeviceIDs.contains(id) }

    func deviceInfo(for id: String) -> ProximityDeviceInfo {
        let device = devices.first(where: { $0.id == id })
            ?? knownDevices[id]
            ?? ProximityDeviceInfo(id: id,
                                   name: id.hasPrefix("ble:privio:") ? "PrivioWear Watch" : id,
                                   kind: id.hasPrefix("ble:privio:") ? .watch : .other,
                                   isConnected: false, rssi: nil, batteryPercent: nil)
        guard let customName = PrivioBeaconPairingStore.shared.displayName(for: id) else { return device }
        return ProximityDeviceInfo(id: device.id, name: customName, kind: device.kind,
                                   isConnected: device.isConnected, rssi: device.rssi,
                                   batteryPercent: device.batteryPercent)
    }

    private func evaluate() {
        guard !isSnapshot else { return }
        let byID = Dictionary(devices.map { ($0.id, $0.reading) }, uniquingKeysWith: { _, last in last })
        let readings = config.trustedDeviceIDs.map { id in
            let device = devices.first(where: { $0.id == id }) ?? knownDevices[id]
            // Klasyczny status zegarka Wear OS miga połączeniem i nie jest wiarygodnym
            // sygnałem obecności. Nigdy nie pozwól mu uzbroić polityki.
            if !id.hasPrefix("ble:"), device?.kind == .watch {
                return ProximityDeviceReading(deviceID: id, isConnected: false)
            }
            return byID[id] ?? ProximityDeviceReading(deviceID: id, isConnected: false)
        }
        let decision = policy.evaluate(readings: readings, config: config, at: Date())
        let readSummary = readings.map { r in
            "\(r.deviceID.suffix(6)) conn=\(r.isConnected) rssi=\(r.rssi.map(String.init) ?? "nil")"
        }.joined(separator: " | ")
        ProximityDiag.log("policy: thr=\(config.rssiThreshold) armed=\(policy.isArmed) autoPaused=\(policy.isAutoPaused) decision=\(decision) readings=[\(readSummary)]")
        switch decision {
        case .none:
            break
        case .lock(let target):
            ProximityDiag.log("policy: LOCK target=\(target)")
            switch target {
            case .screen:
                screenLock.lockScreen()
            case .protectedApps:
                onLockProtectedApps?()
                onLockVault?()
            }
        case .autoPaused:
            ProximityDiag.log("policy: AUTO-PAUSED (circuit breaker)")
            autoPausedNotice = true
            onPersistPaused?(true)
        }
    }

    /// Przykładowe urządzenia dla trybu snapshot (bez realnego Bluetooth).
    static let sampleDevices: [ProximityDeviceInfo] = [
        ProximityDeviceInfo(id: "AA-BB-CC-11-22-33", name: "iPhone Kuby", kind: .phone,
                            isConnected: true, rssi: -52, batteryPercent: 78),
        ProximityDeviceInfo(id: "DD-EE-FF-44-55-66", name: "AirPods Pro", kind: .headphones,
                            isConnected: true, rssi: -68, batteryPercent: 45),
        ProximityDeviceInfo(id: "11-22-33-44-55-66", name: "Apple Watch", kind: .watch,
                            isConnected: false, rssi: nil, batteryPercent: nil)
    ]
}
