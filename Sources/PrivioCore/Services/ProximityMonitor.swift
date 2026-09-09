import Foundation

/// Rodzaj urządzenia - tylko do ikony/etykiety w UI.
public enum ProximityDeviceKind: String, Sendable, Codable {
    case phone, watch, headphones, mouse, keyboard, other
}

/// Widoczne w UI sparowane urządzenie Bluetooth z bieżącym stanem. `rssi`/`battery`
/// mogą być `nil`, gdy system ich nie udostępnia (patrz Post-MVP §3, ograniczenia).
public struct ProximityDeviceInfo: Identifiable, Sendable, Hashable {
    public let id: String            // stabilny identyfikator (adres sparowanego urządzenia)
    public let name: String
    public let kind: ProximityDeviceKind
    public let isConnected: Bool
    public let rssi: Int?
    public let batteryPercent: Int?

    public init(id: String, name: String, kind: ProximityDeviceKind = .other,
                isConnected: Bool, rssi: Int? = nil, batteryPercent: Int? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isConnected = isConnected
        self.rssi = rssi
        self.batteryPercent = batteryPercent
    }

    /// Odczyt dla polityki decyzyjnej (bez nazwy - polityka jej nie potrzebuje).
    public var reading: ProximityDeviceReading {
        ProximityDeviceReading(deviceID: id, isConnected: isConnected, rssi: rssi, batteryPercent: batteryPercent)
    }
}

/// Źródło stanu urządzeń Bluetooth. Produkcyjny `BluetoothProximityMonitor`
/// (IOBluetooth) żyje w warstwie aplikacji; `ManualProximityMonitor` służy testom
/// i trybowi snapshot - analogicznie do `ManualInactivityScheduler`.
public protocol ProximityMonitoring: AnyObject, Sendable {
    /// Strumień aktualnych list sparowanych urządzeń z żywym stanem (połączenie/RSSI/bateria).
    /// Emituje bieżącą migawkę od razu, a potem przy każdej zmianie/odpytaniu.
    func deviceUpdates() -> AsyncStream<[ProximityDeviceInfo]>
    /// Start cyklicznego odpytywania (idempotentny).
    func start()
    /// Zatrzymanie odpytywania.
    func stop()
}

/// Deterministyczny monitor do testów i snapshotu - ręcznie ustawiasz listę urządzeń.
public final class ManualProximityMonitor: ProximityMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var devices: [ProximityDeviceInfo]
    private var continuations: [UUID: AsyncStream<[ProximityDeviceInfo]>.Continuation] = [:]

    public init(devices: [ProximityDeviceInfo] = []) {
        self.devices = devices
    }

    public func deviceUpdates() -> AsyncStream<[ProximityDeviceInfo]> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            let snapshot = devices
            lock.unlock()
            continuation.yield(snapshot)
            continuation.onTermination = { [weak self] _ in
                self?.lock.lock(); self?.continuations[id] = nil; self?.lock.unlock()
            }
        }
    }

    public func start() {}
    public func stop() {}

    /// Podmienia listę urządzeń i rozgłasza ją subskrybentom (dla testów).
    public func set(_ devices: [ProximityDeviceInfo]) {
        lock.lock()
        self.devices = devices
        let subs = Array(continuations.values)
        lock.unlock()
        subs.forEach { $0.yield(devices) }
    }
}
