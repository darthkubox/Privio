import XCTest
@testable import PrivioCore

final class ProximityLockPolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private func config(devices: [String] = ["A"],
                        target: ProximityLockTarget = .screen,
                        debounce: Int = 15,
                        grace: Int = 60,
                        rssi: Int = -75,
                        lowBattery: Int = 15) -> ProximityConfig {
        ProximityConfig(enabled: true, trustedDeviceIDs: devices, lockTarget: target,
                        awayDebounceSeconds: debounce, graceAfterUnlockSeconds: grace,
                        rssiThreshold: rssi, lowBatteryThreshold: lowBattery, paused: false)
    }

    private func present(_ id: String, rssi: Int? = -50, battery: Int? = nil) -> ProximityDeviceReading {
        ProximityDeviceReading(deviceID: id, isConnected: true, rssi: rssi, batteryPercent: battery)
    }
    private func away(_ id: String) -> ProximityDeviceReading {
        ProximityDeviceReading(deviceID: id, isConnected: false)
    }

    // MARK: - Warstwa 1: nieobecność „w spoczynku" nie blokuje

    func testAbsenceAtRestNeverLocks() {
        var p = ProximityLockPolicy()
        let cfg = config()
        XCTAssertEqual(p.evaluate(readings: [away("A")], config: cfg, at: t0), .none)
        XCTAssertEqual(p.evaluate(readings: [away("A")], config: cfg, at: at(1000)), .none)
        XCTAssertFalse(p.isArmed)
    }

    func testMissingDeviceReadingCountsAsAbsentButDoesNotLockAtRest() {
        var p = ProximityLockPolicy()
        let cfg = config()
        // Brak jakiegokolwiek odczytu dla A - nieobecny, ale nigdy nie był obecny.
        XCTAssertEqual(p.evaluate(readings: [], config: cfg, at: t0), .none)
        XCTAssertEqual(p.evaluate(readings: [], config: cfg, at: at(500)), .none)
    }

    // MARK: - Warstwa 5: edge-trigger + debounce

    func testLocksOnPresentToAwayAfterDebounce() {
        var p = ProximityLockPolicy()
        let cfg = config(debounce: 15, grace: 0)
        XCTAssertEqual(p.evaluate(readings: [present("A")], config: cfg, at: t0), .none)     // arm
        XCTAssertTrue(p.isArmed)
        XCTAssertEqual(p.evaluate(readings: [away("A")], config: cfg, at: at(1)), .none)     // away start
        XCTAssertEqual(p.evaluate(readings: [away("A")], config: cfg, at: at(10)), .none)    // < debounce
        XCTAssertEqual(p.evaluate(readings: [away("A")], config: cfg, at: at(20)), .lock(.screen)) // >= debounce
    }

    func testRespectsLockTarget() {
        var p = ProximityLockPolicy()
        let cfg = config(target: .protectedApps, debounce: 5, grace: 0)
        _ = p.evaluate(readings: [present("A")], config: cfg, at: t0)
        _ = p.evaluate(readings: [away("A")], config: cfg, at: at(1))
        XCTAssertEqual(p.evaluate(readings: [away("A")], config: cfg, at: at(10)), .lock(.protectedApps))
    }

    // MARK: - Warstwa 10: próg RSSI

    func testWeakRSSIWhileConnectedCountsAsAway() {
        var p = ProximityLockPolicy()
        let cfg = config(debounce: 10, grace: 0, rssi: -75)
        _ = p.evaluate(readings: [present("A", rssi: -50)], config: cfg, at: t0)  // silny sygnał → obecny
        // Połączony, ale sygnał słabszy niż próg → traktowany jak oddalony.
        _ = p.evaluate(readings: [present("A", rssi: -90)], config: cfg, at: at(1))
        XCTAssertEqual(p.evaluate(readings: [present("A", rssi: -90)], config: cfg, at: at(12)), .lock(.screen))
    }

    func testUnknownRSSITrustsConnectionState() {
        var p = ProximityLockPolicy()
        let cfg = config(debounce: 5, grace: 0)
        // rssi nil, ale połączony → obecny (nie blokuje).
        XCTAssertEqual(p.evaluate(readings: [present("A", rssi: nil)], config: cfg, at: t0), .none)
        XCTAssertTrue(p.isArmed)
    }

    // MARK: - Warstwa 3: re-uzbrojenie tylko po ponownej obecności

    func testDoesNotLockTwiceWithoutReobservingPresence() {
        var p = ProximityLockPolicy()
        let cfg = config(debounce: 10, grace: 0)
        _ = p.evaluate(readings: [present("A")], config: cfg, at: t0)
        _ = p.evaluate(readings: [away("A")], config: cfg, at: at(1))
        XCTAssertEqual(p.evaluate(readings: [away("A")], config: cfg, at: at(12)), .lock(.screen))
        // Dalej nieobecny, bez ponownej obecności → żadnej kolejnej blokady.
        XCTAssertEqual(p.evaluate(readings: [away("A")], config: cfg, at: at(60)), .none)
        XCTAssertEqual(p.evaluate(readings: [away("A")], config: cfg, at: at(600)), .none)
    }

    func testRearmsAfterPresenceThenLocksAgain() {
        var p = ProximityLockPolicy()
        let cfg = config(debounce: 10, grace: 0)
        _ = p.evaluate(readings: [present("A")], config: cfg, at: t0)
        _ = p.evaluate(readings: [away("A")], config: cfg, at: at(1))
        XCTAssertEqual(p.evaluate(readings: [away("A")], config: cfg, at: at(12)), .lock(.screen))
        // Zgubione urządzenie wraca → obecność uzbraja ponownie.
        _ = p.evaluate(readings: [present("A")], config: cfg, at: at(300))
        _ = p.evaluate(readings: [away("A")], config: cfg, at: at(301))
        XCTAssertEqual(p.evaluate(readings: [away("A")], config: cfg, at: at(312)), .lock(.screen))
    }

    // MARK: - Warstwa 4: karencja po odblokowaniu

    func testGraceAfterUnlockSuppressesLockUntilElapsed() {
        var p = ProximityLockPolicy()
        let cfg = config(debounce: 10, grace: 60)
        _ = p.evaluate(readings: [present("A")], config: cfg, at: t0)
        p.noteUnlock(at: t0, config: cfg)               // karencja do t0+60, DISARM
        _ = p.evaluate(readings: [present("A")], config: cfg, at: at(1))   // ponowna obecność uzbraja
        _ = p.evaluate(readings: [away("A")], config: cfg, at: at(2))      // away start
        // debounce spełniony (>10 s), ale wciąż w karencji → brak blokady
        XCTAssertEqual(p.evaluate(readings: [away("A")], config: cfg, at: at(40)), .none)
        // po karencji → blokuje
        XCTAssertEqual(p.evaluate(readings: [away("A")], config: cfg, at: at(61)), .lock(.screen))
    }

    // MARK: - Warstwa 7: niska bateria wstrzymuje

    func testLowBatterySuppressesLockingUsingLastKnownReading() {
        var p = ProximityLockPolicy()
        let cfg = config(debounce: 10, grace: 0, lowBattery: 15)
        // Ostatni znany odczyt: obecny, bateria 8% (poniżej progu).
        _ = p.evaluate(readings: [present("A", battery: 8)], config: cfg, at: t0)
        // Urządzenie znika (rozłączone, bateria nieznana) - ale pamiętamy 8% → wstrzymanie.
        _ = p.evaluate(readings: [away("A")], config: cfg, at: at(1))
        XCTAssertEqual(p.evaluate(readings: [away("A")], config: cfg, at: at(30)), .none)
    }

    func testNormalBatteryDoesNotSuppress() {
        var p = ProximityLockPolicy()
        let cfg = config(debounce: 10, grace: 0, lowBattery: 15)
        _ = p.evaluate(readings: [present("A", battery: 80)], config: cfg, at: t0)
        _ = p.evaluate(readings: [away("A")], config: cfg, at: at(1))
        XCTAssertEqual(p.evaluate(readings: [away("A")], config: cfg, at: at(30)), .lock(.screen))
    }

    // MARK: - Warstwa 6: bezpiecznik (circuit breaker)

    func testCircuitBreakerAutoPausesAfterRepeatedLocks() {
        var p = ProximityLockPolicy()
        // Debounce klampuje się do min. 5 s - używamy tego minimum i okien > 5 s.
        let cfg = config(debounce: 5, grace: 15)
        // Trzy cykle obecny→oddalony w oknie bezpiecznika (120 s).
        func flap(base: TimeInterval) -> ProximityDecision {
            _ = p.evaluate(readings: [present("A")], config: cfg, at: at(base))
            _ = p.evaluate(readings: [away("A")], config: cfg, at: at(base + 0.1))
            return p.evaluate(readings: [away("A")], config: cfg, at: at(base + 6))
        }
        XCTAssertEqual(flap(base: 0), .lock(.screen))
        XCTAssertEqual(flap(base: 20), .lock(.screen))
        XCTAssertEqual(flap(base: 40), .autoPaused)     // trzecia blokada w oknie → auto-pauza
        XCTAssertTrue(p.isAutoPaused)
        // Po auto-pauzie nic nie blokuje…
        _ = p.evaluate(readings: [present("A")], config: cfg, at: at(60))
        _ = p.evaluate(readings: [away("A")], config: cfg, at: at(61))
        XCTAssertEqual(p.evaluate(readings: [away("A")], config: cfg, at: at(80)), .none)
        // …dopóki użytkownik ręcznie nie wznowi.
        p.resume()
        XCTAssertFalse(p.isAutoPaused)
        _ = p.evaluate(readings: [present("A")], config: cfg, at: at(100))
        _ = p.evaluate(readings: [away("A")], config: cfg, at: at(101))
        XCTAssertEqual(p.evaluate(readings: [away("A")], config: cfg, at: at(110)), .lock(.screen))
    }

    // MARK: - Warstwa 8 / stany wyłączające

    func testDisabledOrPausedNeverLocks() {
        var p = ProximityLockPolicy()
        var cfg = config(debounce: 5, grace: 0)
        _ = p.evaluate(readings: [present("A")], config: cfg, at: t0)   // arm
        cfg.paused = true
        _ = p.evaluate(readings: [away("A")], config: cfg, at: at(1))
        XCTAssertEqual(p.evaluate(readings: [away("A")], config: cfg, at: at(30)), .none)
        // Wznowienie wymaga ponownej obecności (rozbrojone podczas pauzy).
        cfg.paused = false
        XCTAssertEqual(p.evaluate(readings: [away("A")], config: cfg, at: at(31)), .none)
    }

    func testEmptyTrustedDevicesNeverLocks() {
        var p = ProximityLockPolicy()
        let cfg = config(devices: [])
        XCTAssertEqual(p.evaluate(readings: [away("A")], config: cfg, at: t0), .none)
    }

    // MARK: - Dwa urządzenia: blokada dopiero, gdy odejdą wszystkie

    func testTwoDevicesLockOnlyWhenAllLeave() {
        var p = ProximityLockPolicy()
        let cfg = config(devices: ["A", "B"], debounce: 10, grace: 0)
        // Oba obecne → uzbrojone.
        XCTAssertEqual(p.evaluate(readings: [present("A"), present("B")], config: cfg, at: t0), .none)
        XCTAssertTrue(p.isArmed)
        // Zniknęło B, ale A dalej obecny → NIE blokuj (którekolwiek w zasięgu = obecny).
        _ = p.evaluate(readings: [present("A"), away("B")], config: cfg, at: at(1))
        XCTAssertEqual(p.evaluate(readings: [present("A"), away("B")], config: cfg, at: at(12)), .none)
        // Odeszły oba → blokada po debounce.
        _ = p.evaluate(readings: [away("A"), away("B")], config: cfg, at: at(13))
        XCTAssertEqual(p.evaluate(readings: [away("A"), away("B")], config: cfg, at: at(30)), .lock(.screen))
    }

    // MARK: - Migotanie krótsze niż debounce nie blokuje (histereza)

    func testBriefAbsenceShorterThanDebounceDoesNotLock() {
        var p = ProximityLockPolicy()
        let cfg = config(debounce: 15, grace: 0)
        _ = p.evaluate(readings: [present("A")], config: cfg, at: t0)   // arm
        _ = p.evaluate(readings: [away("A")], config: cfg, at: at(1))   // away start
        // Wraca przed upływem debounce → reset awaySince, brak blokady.
        _ = p.evaluate(readings: [present("A")], config: cfg, at: at(5))
        _ = p.evaluate(readings: [away("A")], config: cfg, at: at(6))
        XCTAssertEqual(p.evaluate(readings: [away("A")], config: cfg, at: at(18)), .none)    // 18-6=12 < 15
        // Dopiero nieprzerwane oddalenie ≥ debounce blokuje.
        XCTAssertEqual(p.evaluate(readings: [away("A")], config: cfg, at: at(21)), .lock(.screen)) // 21-6=15
    }

    // MARK: - Tolerancja slotu tokenu obecności (rozjazd zegarów)

    func testSlotToleranceAcceptsModeratePastAndFutureSkew() {
        let cur: UInt32 = 1000
        XCTAssertTrue(ProximityBeaconSlot.isSlotAcceptable(advertisedSlot: cur, currentSlot: cur))
        XCTAssertTrue(ProximityBeaconSlot.isSlotAcceptable(advertisedSlot: cur - 4, currentSlot: cur)) // brzeg przeszłości
        XCTAssertTrue(ProximityBeaconSlot.isSlotAcceptable(advertisedSlot: cur + 2, currentSlot: cur)) // brzeg przyszłości
    }

    func testSlotToleranceRejectsFarSkew() {
        let cur: UInt32 = 1000
        XCTAssertFalse(ProximityBeaconSlot.isSlotAcceptable(advertisedSlot: cur - 5, currentSlot: cur)) // za stary
        XCTAssertFalse(ProximityBeaconSlot.isSlotAcceptable(advertisedSlot: cur + 3, currentSlot: cur)) // za daleko w przyszłość
    }

    func testSlotToleranceIsWiderInThePastThanOldSymmetricWindow() {
        // Regresja pierwotnego buga: dawne symetryczne ±1 odrzucało już ~90 s dryfu.
        let cur: UInt32 = 5000
        XCTAssertTrue(ProximityBeaconSlot.isSlotAcceptable(advertisedSlot: cur - 3, currentSlot: cur))
        XCTAssertFalse(ProximityBeaconSlot.isSlotAcceptable(advertisedSlot: cur - 3, currentSlot: cur,
                                                            pastTolerance: 1, futureTolerance: 1))
    }

    func testTwoDevicesStayArmedWhileBothPresent() {
        var p = ProximityLockPolicy()
        let cfg = config(devices: ["A", "B"], debounce: 5, grace: 0)
        XCTAssertEqual(p.evaluate(readings: [present("A"), present("B")], config: cfg, at: t0), .none)
        XCTAssertEqual(p.evaluate(readings: [present("A"), present("B")], config: cfg, at: at(100)), .none)
    }

    // MARK: - ProximityConfig: dekodowanie defensywne + klampowanie

    func testConfigClampsOutOfRangeValues() {
        let cfg = ProximityConfig(awayDebounceSeconds: 9999, graceAfterUnlockSeconds: 0,
                                  rssiThreshold: 999, lowBatteryThreshold: 1)
        XCTAssertEqual(cfg.awayDebounceSeconds, ProximityConfig.awayDebounceRange.upperBound)
        XCTAssertEqual(cfg.graceAfterUnlockSeconds, ProximityConfig.graceRange.lowerBound)
        XCTAssertEqual(cfg.rssiThreshold, ProximityConfig.rssiThresholdRange.upperBound)
        XCTAssertEqual(cfg.lowBatteryThreshold, ProximityConfig.lowBatteryRange.lowerBound)
    }

    func testConfigLimitsTrustedDevices() {
        let cfg = ProximityConfig(trustedDeviceIDs: ["A", "B", "C", "D", "E", "F", "G"])
        XCTAssertEqual(cfg.trustedDeviceIDs.count, ProximityConfig.maxTrustedDevices)
        XCTAssertEqual(cfg.trustedDeviceIDs, ["A", "B", "C", "D", "E"])
    }

    func testAppConfigurationDecodesWithoutProximityKey() throws {
        // Starszy config.json bez pola „proximity" musi dekodować się z domyślnym modułem.
        let json = #"{"startAtLogin":true}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: json)
        XCTAssertFalse(decoded.proximity.enabled)
        XCTAssertEqual(decoded.proximity.lockTarget, .screen)
    }

    func testAppConfigurationRoundTripsProximity() throws {
        var cfg = AppConfiguration.default
        cfg.proximity = ProximityConfig(enabled: true, trustedDeviceIDs: ["dev-1"],
                                        lockTarget: .protectedApps, paused: true)
        let data = try JSONEncoder().encode(cfg)
        let back = try JSONDecoder().decode(AppConfiguration.self, from: data)
        XCTAssertEqual(back.proximity, cfg.proximity)
    }

    // MARK: - Wyłączanie pojedynczego urządzenia (jak apka/strona)

    func testDisabledDeviceIsExcludedFromDecision() {
        var p = ProximityLockPolicy()
        // A aktywne, B wyłączone → decyzja tylko wg A (nieobecne B bez znaczenia).
        let cfg = ProximityConfig(enabled: true, trustedDeviceIDs: ["A", "B"],
                                  disabledDeviceIDs: ["B"], awayDebounceSeconds: 15, rssiThreshold: -75)
        XCTAssertEqual(p.evaluate(readings: [present("A"), away("B")], config: cfg, at: t0), .none)  // arm
        _ = p.evaluate(readings: [away("A"), away("B")], config: cfg, at: at(1))
        XCTAssertEqual(p.evaluate(readings: [away("A"), away("B")], config: cfg, at: at(20)), .lock(.screen))
    }

    func testAllDevicesDisabledNeverLocks() {
        var p = ProximityLockPolicy()
        let cfg = ProximityConfig(enabled: true, trustedDeviceIDs: ["A"], disabledDeviceIDs: ["A"])
        XCTAssertEqual(p.evaluate(readings: [present("A")], config: cfg, at: t0), .none)
        XCTAssertEqual(p.evaluate(readings: [away("A")], config: cfg, at: at(60)), .none)
    }

    // MARK: - Model napędzany RSSI (etui słuchawek nie blokuje, oddalenie zegarka tak)

    func testRSSIDeviceDrivesDecisionOverConnectionOnly() {
        var p = ProximityLockPolicy()
        let cfg = config(devices: ["watch", "buds"], debounce: 15, rssi: -75)
        // Uzbrój: zegarek (RSSI) + słuchawki (tylko połączenie) obecne.
        XCTAssertEqual(p.evaluate(readings: [present("watch", rssi: -50), present("buds", rssi: nil)],
                                  config: cfg, at: t0), .none)
        // Słuchawki do etui (rozłączone), zegarek blisko → NIE blokuj nawet po debounce.
        _ = p.evaluate(readings: [present("watch", rssi: -50), away("buds")], config: cfg, at: at(1))
        XCTAssertEqual(p.evaluate(readings: [present("watch", rssi: -50), away("buds")],
                                  config: cfg, at: at(30)), .none)
        // Zegarek się oddala → blokuj po debounce.
        _ = p.evaluate(readings: [away("watch"), away("buds")], config: cfg, at: at(31))
        XCTAssertEqual(p.evaluate(readings: [away("watch"), away("buds")], config: cfg, at: at(50)), .lock(.screen))
    }
}
