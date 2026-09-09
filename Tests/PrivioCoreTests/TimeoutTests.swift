import XCTest
@testable import PrivioCore

final class TimeoutTests: XCTestCase {

    func testLockPresetSeconds() {
        XCTAssertEqual(LockTimeoutPreset.immediately.seconds, 0)
        XCTAssertEqual(LockTimeoutPreset.after2m.seconds, 120)
        XCTAssertNil(LockTimeoutPreset.never.seconds)
    }

    func testLockPresetFromSeconds() {
        XCTAssertEqual(LockTimeoutPreset.from(seconds: 120), .after2m)
        XCTAssertEqual(LockTimeoutPreset.from(seconds: nil), .never)
        // Najbliższe dopasowanie.
        XCTAssertEqual(LockTimeoutPreset.from(seconds: 55), .after1m)
        XCTAssertEqual(LockTimeoutPreset.from(seconds: 0), .immediately)
    }

    func testQuitPresetRoundTrip() {
        for preset in QuitTimeoutPreset.allCases where preset != .never {
            XCTAssertEqual(QuitTimeoutPreset.from(seconds: preset.seconds), preset)
        }
        XCTAssertEqual(QuitTimeoutPreset.from(seconds: nil), .never)
    }

    func testTimeoutValidationWarnsWhenQuitBeforeLock() {
        // quit (120) < lock (900) → ostrzeżenie
        XCTAssertNotNil(TimeoutValidation.warning(lock: 900, quit: 120))
        // quit (900) > lock (120) → brak ostrzeżenia
        XCTAssertNil(TimeoutValidation.warning(lock: 120, quit: 900))
        // quit == lock → ostrzeżenie (zamknie zanim zablokuje)
        XCTAssertNotNil(TimeoutValidation.warning(lock: 120, quit: 120))
        // quit never → brak konfliktu
        XCTAssertNil(TimeoutValidation.warning(lock: 120, quit: nil))
        // lock never, quit ustawiony → ostrzeżenie (zamknie bez blokady)
        XCTAssertNotNil(TimeoutValidation.warning(lock: nil, quit: 300))
    }

    func testProtectedAppDerivedPresets() {
        let app = ProtectedApp(bundleIdentifier: "com.test.a", displayName: "A",
                               applicationURL: URL(fileURLWithPath: "/Applications/A.app"),
                               lockAfterInactivity: 120, quitAfterInactivity: 60)
        XCTAssertEqual(app.lockPreset, .after2m)
        XCTAssertEqual(app.quitPreset, .after1m)
        XCTAssertNotNil(app.timeoutWarning)   // quit 60 < lock 120
    }
}
