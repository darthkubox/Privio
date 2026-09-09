import Foundation
import IOBluetooth
import IOKit
import PrivioCore

/// Produkcyjny monitor obecności: **sparowane** urządzenia Bluetooth przez publiczne
/// `IOBluetooth` - bez nowych uprawnień (sekcja 29 spec). Odpytuje cyklicznie stan
/// połączenia i RSSI (RSSI dostępny tylko dla połączonych). Bateria: best-effort z
/// IORegistry (część urządzeń Apple ją udostępnia; gdzie brak - `nil`).
final class BluetoothProximityMonitor: ProximityMonitoring, @unchecked Sendable {
    private let pollInterval: TimeInterval
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<[ProximityDeviceInfo]>.Continuation] = [:]
    private var timer: DispatchSourceTimer?
    private let ble = BLEProximityScanner()
    private var bleDevices: [ProximityDeviceInfo] = []
    var onBluetoothState: (@Sendable (BluetoothRadioState) -> Void)?
    var onRemoteLock: (@Sendable () -> Void)?

    init(pollInterval: TimeInterval = 3) {
        self.pollInterval = pollInterval
        ble.onUpdate = { [weak self] devices in self?.storeBLE(devices) }
        ble.onState = { [weak self] state in self?.onBluetoothState?(state) }
        ble.onRemoteLock = { [weak self] in self?.onRemoteLock?() }
    }

    func updateMacLockState(_ locked: Bool) { ble.updateMacLockState(locked) }

    func deviceUpdates() -> AsyncStream<[ProximityDeviceInfo]> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock(); continuations[id] = continuation; lock.unlock()
            continuation.yield(mergedSnapshot())
            continuation.onTermination = { [weak self] _ in
                self?.lock.lock(); self?.continuations[id] = nil; self?.lock.unlock()
            }
        }
    }

    func start() {
        lock.lock()
        if timer == nil {
            // IOBluetooth lubi główny wątek/runloop - odpytujemy na kolejce głównej.
            let t = DispatchSource.makeTimerSource(queue: .main)
            t.schedule(deadline: .now() + 0.1, repeating: pollInterval)
            t.setEventHandler { [weak self] in self?.broadcast() }
            timer = t
            t.resume()
        }
        lock.unlock()
        ble.start()   // równolegle skanuj BLE (pobliskie, niesparowane urządzenia)
    }

    func stop() {
        lock.lock(); timer?.cancel(); timer = nil; lock.unlock()
        ble.stop()
    }

    private func storeBLE(_ devices: [ProximityDeviceInfo]) {
        lock.lock(); bleDevices = devices; lock.unlock()
        broadcast()
    }

    private func broadcast() {
        let devices = mergedSnapshot()
        lock.lock(); let subs = Array(continuations.values); lock.unlock()
        subs.forEach { $0.yield(devices) }
    }

    /// Sparowane (klasyczne, z baterią) + pobliskie BLE. Deduplikacja po nazwie -
    /// przy kolizji wybieramy wpis DAJĄCY OBECNOŚĆ (np. zegarek, który klasycznie tylko
    /// „mignie" połączeniem, ale stale rozgłasza się po BLE, ma tam żywy RSSI).
    private func mergedSnapshot() -> [ProximityDeviceInfo] {
        let classic = Self.classicSnapshot()
        lock.lock(); let bleList = bleDevices; lock.unlock()
        var byName: [String: ProximityDeviceInfo] = [:]
        for device in classic + bleList {
            let key = device.name.lowercased()
            byName[key] = byName[key].map { Self.moreUseful($0, device) } ?? device
        }
        return byName.values.sorted { ($0.rssi ?? -999) > ($1.rssi ?? -999) }
    }

    /// Przy tej samej nazwie: połączony > z żywym RSSI > pozostałe.
    private static func moreUseful(_ a: ProximityDeviceInfo, _ b: ProximityDeviceInfo) -> ProximityDeviceInfo {
        if a.isConnected != b.isConnected { return a.isConnected ? a : b }
        if (a.rssi != nil) != (b.rssi != nil) { return a.rssi != nil ? a : b }
        return a
    }

    private static func classicSnapshot() -> [ProximityDeviceInfo] {
        let batteries = batteryByAddress()
        let raw = IOBluetoothDevice.pairedDevices()
        let paired = (raw as? [IOBluetoothDevice]) ?? []
        ProximityDiag.log("classic: raw=\(raw == nil ? "nil" : "count=\(raw?.count ?? -1)") parsed=\(paired.count) names=[\(paired.compactMap { $0.name ?? $0.addressString }.joined(separator: ", "))] batteries=\(batteries.count)")
        return paired.compactMap { device in
            guard let address = device.addressString, !address.isEmpty else { return nil }
            let connected = device.isConnected()
            let name = device.name ?? address
            return ProximityDeviceInfo(
                id: address,
                name: name,
                kind: kind(for: device, name: name),
                isConnected: connected,
                rssi: connected ? validRSSI(device) : nil,
                batteryPercent: batteries[normalize(address)]
            )
        }
    }

    /// Realne RSSI jest zawsze ujemne (dBm poniżej 0). `rawRSSI` zwraca 127 (0x7F),
    /// gdy wartość jest niedostępna, a wiele klasycznych urządzeń (np. słuchawki
    /// WF-1000XM5) zwraca 0 przy braku otwartego połączenia baseband. Każde `>= 0`
    /// traktujemy więc jako „brak odczytu" (nil) - inaczej 0 dBm udawałoby „zawsze w
    /// zasięgu" i oddalenie nigdy by się nie wyzwoliło. Przy nil obecność opiera się
    /// na samym stanie połączenia (blokada, gdy urządzenie się rozłączy/wyjdzie poza zasięg).
    private static func validRSSI(_ device: IOBluetoothDevice) -> Int? {
        let raw = Int(device.rawRSSI())
        return raw >= 0 ? nil : raw
    }

    /// Typ urządzenia: najpierw pewne **Class of Device** (major class z Bluetooth,
    /// niezależne od nazwy - np. Sony WF‑1000XM5 zgłasza się jako Audio), potem
    /// dopasowanie po nazwie jako uzupełnienie (myszka/klawiatura, marki słuchawek).
    private static func kind(for device: IOBluetoothDevice, name: String) -> ProximityDeviceKind {
        // Bluetooth CoD - major device class (stałe z Assigned Numbers).
        switch Int(device.deviceClassMajor) {
        case 0x04: return .headphones          // Audio/Video (słuchawki, głośniki)
        case 0x02: return .phone               // Phone
        case 0x07: return .watch               // Wearable (zegarek)
        case 0x05:                             // Peripheral (mysz/klawiatura)
            let minor = Int(device.deviceClassMinor)
            if minor & 0x40 != 0 { return .keyboard }   // bit klawiatury
            if minor & 0x80 != 0 { return .mouse }      // bit urządzenia wskazującego
        default: break
        }
        return kind(forName: name)
    }

    private static func kind(forName name: String) -> ProximityDeviceKind {
        let n = name.lowercased()
        if n.contains("airpod") || n.contains("buds") || n.contains("headphone")
            || n.contains("headset") || n.contains("beats") || n.contains("słuchaw")
            || n.contains("wf-") || n.contains("wh-") || n.contains("wi-")       // Sony
            || n.contains("bose") || n.contains("quietcomfort") || n.contains("qc")
            || n.contains("jabra") || n.contains("sennheiser") || n.contains("momentum")
            || n.contains("jbl") || n.contains("soundcore") || n.contains("earbuds")
            || n.contains("earphone") || n.contains("freebuds") { return .headphones }
        if n.contains("watch") || n.contains("zegar") || n.contains("band")
            || n.contains("wear") { return .watch }
        if n.contains("iphone") || n.contains("phone") || n.contains("pixel")
            || n.contains("galaxy") || n.contains("telefon") { return .phone }
        if n.contains("trackpad") || n.contains("mouse") || n.contains("mysz")
            || n.contains("mx master") || n.contains("mx anywhere") { return .mouse }
        if n.contains("keyboard") || n.contains("klawiat")
            || n.contains("mx keys") || n.contains("mx mechanical") { return .keyboard }
        return .other
    }

    private static func normalize(_ address: String) -> String {
        address.lowercased().filter { $0.isHexDigit }
    }

    /// Best-effort: mapa adres→bateria(%) z IORegistry (`AppleDeviceManagementHIDEventService`).
    /// Zwraca `[:]`, gdy cokolwiek zawiedzie - wtedy UI pokazuje „-", a polityka i tak
    /// nie polega na baterii, jeśli jej nie zna.
    private static func batteryByAddress() -> [String: Int] {
        var result: [String: Int] = [:]
        guard let matching = IOServiceMatching("AppleDeviceManagementHIDEventService") else { return result }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return result }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let percent = (dict["BatteryPercent"] as? NSNumber)?.intValue,
               let address = dict["DeviceAddress"] as? String {
                result[normalize(address)] = percent
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return result
    }
}
