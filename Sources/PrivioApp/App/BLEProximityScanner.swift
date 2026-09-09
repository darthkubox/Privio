import CoreBluetooth
import CryptoKit
import Foundation
import PrivioCore

enum BluetoothRadioState: Sendable, Equatable {
    case unknown, resetting, unsupported, unauthorized, poweredOff, poweredOn

    init(_ state: CBManagerState) {
        switch state {
        case .unknown: self = .unknown
        case .resetting: self = .resetting
        case .unsupported: self = .unsupported
        case .unauthorized: self = .unauthorized
        case .poweredOff: self = .poweredOff
        case .poweredOn: self = .poweredOn
        @unknown default: self = .unknown
        }
    }
}

/// Skaner Bluetooth **LE**: wykrywa POBLISKIE urządzenia rozgłaszające się przez BLE
/// (np. zegarki/opaski, których nie da się sparować klasycznie z Makiem) - **bez
/// parowania**. Identyfikuje po **nazwie reklamy** (odporne na rotację losowego
/// adresu BLE), a „obecność" = widziane niedawno z sensownym RSSI.
///
/// Wymaga zgody Bluetooth - Privio ma `NSBluetoothAlwaysUsageDescription`, więc przy
/// pierwszym użyciu system pyta o pozwolenie (a nie crashuje jak narzędzie CLI).
final class BLEProximityScanner: NSObject, @unchecked Sendable {
    static let privioBeaconService = CBUUID(string: "FFF0")
    static let privioControlCharacteristic = CBUUID(string: "FFF1")
    static let privioIdentityCharacteristic = CBUUID(string: "FFF2")
    private let queue = DispatchQueue(label: "com.privio.ble")
    private var central: CBCentralManager?
    private var seen: [String: (label: String, kind: ProximityDeviceKind, rssi: Int, at: Date)] = [:]
    private var lastManufacturerLog: [UUID: Date] = [:]
    private var wantScan = false
    private var emitTimer: DispatchSourceTimer?
    private var connectedBeacons: [UUID: (peripheral: CBPeripheral, pairing: PrivioBeaconPairing)] = [:]
    private var controlCharacteristics: [UUID: CBCharacteristic] = [:]
    private var acceptedLockPackets: [Data: Date] = [:]
    private var macIsLocked = false
    private var lastStatusSent = Date.distantPast
    /// Okno „świeżości" advertu - advert LOW_POWER przychodzi ~co 1 s i bywa gubiony,
    /// więc szersze okno toleruje kilka strat pod rząd, zanim uznamy urządzenie za
    /// nieobecne (współgra z `awayDebounceSeconds`).
    private static let stalenessWindow: TimeInterval = 20
    /// A2 (watchdog): kiedy ostatnio DOWOLNY advert dotarł do skanera. Gdy macOS zdławi
    /// skan `AllowDuplicates`, adverty milkną całkowicie - wtedy restartujemy skan.
    private var lastAdvertAt = Date.distantPast
    private var lastScanRestart = Date.distantPast
    /// A5: ID urządzeń pokazanych w poprzednim ticku - do logu przejścia present→absent.
    private var lastShownIDs: Set<String> = []
    /// A5: dławienie logu „widziano" per klucz urządzenia.
    private var lastSeenLog: [String: Date] = [:]

    /// Wołane cyklicznie z bieżącą migawką wykrytych, nazwanych urządzeń.
    var onUpdate: (@Sendable ([ProximityDeviceInfo]) -> Void)?
    /// Rzeczywisty stan CoreBluetooth; bardziej wiarygodny niż statyczne
    /// `CBManager.authorization` po zmianie podpisu lokalnego buildu.
    var onState: (@Sendable (BluetoothRadioState) -> Void)?
    /// Zweryfikowana komenda z wcześniej sparowanego zegarka. Może tylko blokować.
    var onRemoteLock: (@Sendable () -> Void)?

    func updateMacLockState(_ locked: Bool) {
        queue.async { [weak self] in
            self?.macIsLocked = locked
            self?.sendMacStatusToConnectedWatches()
        }
    }

    func start() {
        queue.async { [self] in
            wantScan = true
            lastAdvertAt = Date()   // daj watchdogowi karencję po starcie
            if central == nil {
                central = CBCentralManager(delegate: self, queue: queue)   // uruchamia prompt o zgodę
            } else {
                beginScan()
            }
            startEmitTimer()
        }
    }

    func stop() {
        queue.async { [self] in
            wantScan = false
            central?.stopScan()
            for connection in connectedBeacons.values { central?.cancelPeripheralConnection(connection.peripheral) }
            connectedBeacons.removeAll()
            controlCharacteristics.removeAll()
            seen.removeAll()
            lastShownIDs.removeAll()
            emitTimer?.cancel(); emitTimer = nil
        }
    }

    private func startEmitTimer() {
        guard emitTimer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 2)   // emituj ~co 2 s, nie na każdą reklamę
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.restartScanIfStalled()
            self.pollConnectedRSSI()
            let devices = self.currentDevices()
            if Date().timeIntervalSince(self.lastStatusSent) >= 20 {
                self.sendMacStatusToConnectedWatches()
            }
            self.logLeftWindow(current: devices)
            self.onUpdate?(devices)
        }
        emitTimer = t
        t.resume()
    }

    /// Urządzenia widziane w oknie `stalenessWindow`, najbliższe najpierw.
    private func currentDevices() -> [ProximityDeviceInfo] {
        let cutoff = Date().addingTimeInterval(-Self.stalenessWindow)
        return seen.compactMap { key, v in
            v.at >= cutoff ? ProximityDeviceInfo(
                id: "ble:\(key)", name: v.label, kind: v.kind,
                isConnected: true, rssi: v.rssi, batteryPercent: nil) : nil
        }.sorted { ($0.rssi ?? -999) > ($1.rssi ?? -999) }
    }

    /// A2: gdy przez `>8 s` nie dotarł żaden advert (macOS zdławił skan), restartuj skan
    /// - z dławieniem `>10 s` między restartami, by realnie nieobecne urządzenie nie
    /// kręciło radiem w kółko.
    private func restartScanIfStalled() {
        guard wantScan, central?.state == .poweredOn else { return }
        let now = Date()
        guard now.timeIntervalSince(lastAdvertAt) > 8,
              now.timeIntervalSince(lastScanRestart) > 10 else { return }
        lastScanRestart = now
        central?.stopScan()
        beginScan()
    }

    /// Model połączeniowy (jak parowanie z telefonem): dopóki Mac trzyma połączenie GATT
    /// z zegarkiem, odczytujemy RSSI na żywym łączu i **odświeżamy `seen`** - obecność
    /// niesie samo połączenie (utrzymywane przez kontroler BT, przeżywa Doze), więc
    /// zegarek nie musi ciągle rozgłaszać ani rotować tokenu (oszczędza baterię).
    private func pollConnectedRSSI() {
        for connection in connectedBeacons.values where connection.peripheral.state == .connected {
            connection.peripheral.readRSSI()
        }
    }

    /// A5: loguj urządzenia, które właśnie wypadły z okna świeżości (present→absent) -
    /// najważniejsza linia do diagnozy fałszywej blokady.
    private func logLeftWindow(current devices: [ProximityDeviceInfo]) {
        let shown = Set(devices.map { $0.id })
        for id in lastShownIDs.subtracting(shown) {
            let key = String(id.dropFirst("ble:".count))
            if let v = seen[key] {
                let age = Date().timeIntervalSince(v.at)
            } else {
            }
        }
        lastShownIDs = shown
    }

    private func beginScan() {
        guard let central, central.state == .poweredOn, wantScan else { return }
        // allowDuplicates: świeży RSSI; emisję i tak dławi `emitTimer`.
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    private static func kind(_ name: String) -> ProximityDeviceKind {
        let n = name.lowercased()
        if n.contains("watch") || n.contains("zegar") || n.contains("band") || n.contains("opaska") { return .watch }
        if n.contains("buds") || n.contains("airpod") || n.contains("headphone") || n.contains("beats") { return .headphones }
        if n.contains("iphone") || n.contains("phone") || n.contains("galaxy") || n.contains("pixel") { return .phone }
        return .other
    }

    /// Marka z danych producenta reklamy (16-bit company id, little-endian). Dla marek
    /// urządzeń noszonych; Apple pomijamy (zbyt liczne, zwykle i tak mają nazwę).
    private static func brand(_ adv: [String: Any]) -> String? {
        guard let data = adv[CBAdvertisementDataManufacturerDataKey] as? Data, data.count >= 2 else { return nil }
        let company = UInt16(data[0]) | (UInt16(data[1]) << 8)
        switch company {
        case 0x0075: return "Samsung"
        case 0x0087: return "Garmin"
        case 0x00E0: return "Google/Fitbit"
        case 0x0157: return "Amazfit"
        case 0x038F: return "Xiaomi"
        case 0x006B: return "Polar"
        case 0x0224: return "Withings"
        default: return nil
        }
    }

    private static func shortId(_ id: UUID) -> String { String(id.uuidString.prefix(4)) }

    /// Protokół Privio Beacon v1: `PV`, wersja 1, następnie trwałe 8 bajtów ID.
    /// Adres BLE zegarka może rotować; ID w service data pozostaje stabilne.
    private static func privioBeaconID(_ adv: [String: Any]) -> String? {
        guard let services = adv[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
              let data = services[privioBeaconService], data.count == 11,
              data[0] == 0x50, data[1] == 0x56 else { return nil }
        if data[2] == 0x01 {
            return data.dropFirst(3).map { String(format: "%02X", $0) }.joined()
        }
        guard data[2] == 0x02 else { return nil }
        let counterBytes = Data(data[3...6])
        let advertisedSlot = counterBytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let currentSlot = ProximityBeaconSlot.currentSlot()
        let pairings = PrivioBeaconPairingStore.shared.all()
        let slotDelta = Int64(advertisedSlot) - Int64(currentSlot)
        // Tolerancja asymetryczna (patrz `ProximityBeaconSlot`): szeroko w przeszłość,
        // wąsko w przyszłość - eliminuje fałszywe „odejścia" przy dryfie zegarów.
        guard ProximityBeaconSlot.isSlotAcceptable(advertisedSlot: advertisedSlot,
                                                   currentSlot: currentSlot) else {
            return nil
        }
        let message = Data([0x50, 0x56, 0x02]) + counterBytes
        let advertisedTag = Data(data[7...10])
        for pairing in pairings {
            let key = SymmetricKey(data: pairing.secret)
            let expected = Data(HMAC<SHA256>.authenticationCode(for: message, using: key).prefix(4))
            if advertisedTag == expected { return pairing.id }
        }
        return nil
    }

    static func formattedPairingCode(fromDeviceID id: String) -> String? {
        guard id.hasPrefix("ble:privio:"), let raw = id.split(separator: ":").last,
              raw.count == 16 else { return nil }
        return stride(from: 0, to: raw.count, by: 4).map { offset in
            let start = raw.index(raw.startIndex, offsetBy: offset)
            let end = raw.index(start, offsetBy: 4)
            return String(raw[start..<end])
        }.joined(separator: "-")
    }
}

extension BLEProximityScanner: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        onState?(BluetoothRadioState(c.state))
        if c.state == .poweredOn { beginScan() }
        onUpdate?(currentDevices())
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let rssi = RSSI.intValue
        guard rssi < 0, rssi > -100 else { return }      // odrzuć bardzo słabe/„nieznane"
        lastAdvertAt = Date()                            // A2: skan żyje (dowolny advert)
        if let beaconID = Self.privioBeaconID(advertisementData) {
            let deviceID = "ble:privio:\(beaconID)"
            let label = PrivioBeaconPairingStore.shared.displayName(for: deviceID)
                ?? "PrivioWear Watch"
            let key = "privio:\(beaconID)"
            seen[key] = (label, .watch, rssi, Date())
            if Date().timeIntervalSince(lastSeenLog[key] ?? .distantPast) > 10 {
                lastSeenLog[key] = Date()
            }
            if connectedBeacons[p.identifier] == nil,
               let pairing = PrivioBeaconPairingStore.shared.pairing(for: deviceID) {
                p.delegate = self
                connectedBeacons[p.identifier] = (p, pairing)
                c.connect(p, options: nil)
            }
            return
        }
        let advName = (p.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String))
            .flatMap { $0.isEmpty ? nil : $0 }
        if let advName {
            // Urządzenie z nazwą - klucz stabilny po nazwie.
            seen["name:\(advName)"] = (advName, Self.kind(advName), rssi, Date())
        } else if let brand = Self.brand(advertisementData) {
            // Anonimowe reklamy producentów mają rotujące identyfikatory i nie da się
            // bezpiecznie przypisać ich do konkretnego urządzenia użytkownika. Zachowujemy
            // diagnostykę Samsunga, ale nie pokazujemy tych wpisów na liście wyboru.
            if brand == "Samsung", Date().timeIntervalSince(lastManufacturerLog[p.identifier] ?? .distantPast) > 10,
               let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
                lastManufacturerLog[p.identifier] = Date()
                let payload = data.map { String(format: "%02x", $0) }.joined()
            }
        }
    }

    private func sendMacStatusToConnectedWatches() {
        guard let central else { return }
        lastStatusSent = Date()
        for (id, characteristic) in controlCharacteristics {
            guard let connection = connectedBeacons[id],
                  connection.peripheral.state == .connected else { continue }
            let packet = authenticatedPacket(type: 0x10,
                                             payload: Data([macIsLocked ? 1 : 0]),
                                             secret: connection.pairing.secret)
            connection.peripheral.writeValue(packet, for: characteristic, type: .withResponse)
        }
        _ = central // utrzymuj jawne powiązanie operacji z kolejką central managera
    }

    private func authenticatedPacket(type: UInt8, payload: Data, secret: Data) -> Data {
        let slot = UInt32(Date().timeIntervalSince1970 / 30)
        var bigEndianSlot = slot.bigEndian
        var body = Data([0x50, 0x56, type])
        withUnsafeBytes(of: &bigEndianSlot) { body.append(contentsOf: $0) }
        body.append(payload)
        let tag = Data(HMAC<SHA256>.authenticationCode(for: body, using: SymmetricKey(data: secret)).prefix(8))
        return body + tag
    }

    private func acceptLockPacket(_ data: Data, pairing: PrivioBeaconPairing) -> Bool {
        guard data.count == 19, data[0] == 0x50, data[1] == 0x56, data[2] == 0x11 else { return false }
        let slot = data[3...6].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let current = UInt32(Date().timeIntervalSince1970 / 30)
        guard abs(Int64(slot) - Int64(current)) <= 1 else { return false }
        let body = Data(data[0..<11])
        let expected = Data(HMAC<SHA256>.authenticationCode(
            for: body, using: SymmetricKey(data: pairing.secret)).prefix(8))
        guard expected == Data(data[11..<19]) else { return false }
        let now = Date()
        acceptedLockPackets = acceptedLockPackets.filter { now.timeIntervalSince($0.value) < 90 }
        guard acceptedLockPackets[data] == nil else { return false }
        acceptedLockPackets[data] = now
        return true
    }
}

extension BLEProximityScanner: CBPeripheralDelegate {
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.privioBeaconService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectedBeacons.removeValue(forKey: peripheral.identifier)
        controlCharacteristics.removeValue(forKey: peripheral.identifier)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        timestamp: CFAbsoluteTime, isReconnecting: Bool, error: Error?) {
        connectedBeacons.removeValue(forKey: peripheral.identifier)
        controlCharacteristics.removeValue(forKey: peripheral.identifier)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { return }
        for service in peripheral.services ?? [] where service.uuid == Self.privioBeaconService {
            peripheral.discoverCharacteristics(
                [Self.privioControlCharacteristic, Self.privioIdentityCharacteristic], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { return }
        if let characteristic = service.characteristics?.first(where: { $0.uuid == Self.privioControlCharacteristic }) {
            controlCharacteristics[peripheral.identifier] = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
        }
        if let identity = service.characteristics?.first(where: { $0.uuid == Self.privioIdentityCharacteristic }) {
            peripheral.readValue(for: identity)
        }
        sendMacStatusToConnectedWatches()
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil, let connection = connectedBeacons[peripheral.identifier] else { return }
        let rssi = RSSI.intValue
        guard rssi < 0, rssi > -100 else { return }
        lastAdvertAt = Date()   // żywe połączenie = skan/łącze aktywne (watchdog)
        let key = "privio:\(connection.pairing.id)"
        let label = PrivioBeaconPairingStore.shared.displayName(for: connection.pairing.deviceID)
            ?? "PrivioWear Watch"
        seen[key] = (label, .watch, rssi, Date())   // obecność z połączenia, bez świeżej reklamy
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        if characteristic.uuid == Self.privioIdentityCharacteristic,
           let pairing = connectedBeacons[peripheral.identifier]?.pairing,
           let name = String(data: data, encoding: .utf8) {
            PrivioBeaconPairingStore.shared.setDeviceProvidedName(name, for: pairing.deviceID)
            return
        }
        guard characteristic.uuid == Self.privioControlCharacteristic,
              let pairing = connectedBeacons[peripheral.identifier]?.pairing,
              acceptLockPacket(data, pairing: pairing) else { return }
        onRemoteLock?()
    }
}
