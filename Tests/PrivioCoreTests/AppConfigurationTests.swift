import XCTest
@testable import PrivioCore

final class AppConfigurationTests: XCTestCase {
    func testOlderConfigurationUsesSafeDefaultsForMissingFields() throws {
        let data = Data("{}".utf8)

        let configuration = try JSONDecoder().decode(AppConfiguration.self, from: data)

        XCTAssertEqual(configuration.defaultLockTimeout, 120)
        XCTAssertFalse(configuration.captureFailedAttempts)
        XCTAssertFalse(configuration.privacyModeEnabled)
        XCTAssertEqual(configuration.privacyCurtainMode, .blur)
        XCTAssertEqual(configuration.privacyCurtainScope, .protectedApps)
        XCTAssertEqual(configuration.privacyCurtainSpotlightShape, .circle)
    }

    func testCorruptCurtainEnumsFallBackToDefaults() throws {
        let data = Data(#"{"privacyCurtainMode":"nonsense","privacyCurtainScope":"???"}"#.utf8)

        let configuration = try JSONDecoder().decode(AppConfiguration.self, from: data)

        XCTAssertEqual(configuration.privacyCurtainMode, .blur)
        XCTAssertEqual(configuration.privacyCurtainScope, .protectedApps)
    }

    func testCurtainIntensityAndRadiusAreClampedOnDecode() throws {
        let data = Data(#"{"privacyCurtainIntensity":5,"privacyCurtainSpotlightRadius":9000}"#.utf8)

        let configuration = try JSONDecoder().decode(AppConfiguration.self, from: data)

        XCTAssertEqual(configuration.privacyCurtainIntensity, AppConfiguration.curtainIntensityRange.upperBound)
        XCTAssertEqual(configuration.privacyCurtainSpotlightRadius, AppConfiguration.spotlightRadiusRange.upperBound)
    }

    func testExplicitNeverLockTimeoutRemainsNil() throws {
        let data = Data(#"{"defaultLockTimeout":null}"#.utf8)

        let configuration = try JSONDecoder().decode(AppConfiguration.self, from: data)

        XCTAssertNil(configuration.defaultLockTimeout)
    }

    func testPrivacyModeConfigurationRoundTrip() throws {
        var configuration = AppConfiguration()
        configuration.privacyModeEnabled = true
        configuration.privacyModeShortcut = "control-option-p"
        configuration.privacyRevealHoldShortcut = "control-command"
        configuration.privacyRevealLockShortcut = "control-shift-r"
        configuration.privacyCurtainMode = .spotlight
        configuration.privacyCurtainScope = .fullScreen
        configuration.privacyCurtainIntensity = 0.72
        configuration.privacyCurtainSpotlightRadius = 240
        configuration.privacyCurtainSpotlightShape = .ellipse

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)

        XCTAssertTrue(decoded.privacyModeEnabled)
        XCTAssertEqual(decoded.privacyModeShortcut, "control-option-p")
        XCTAssertEqual(decoded.privacyRevealHoldShortcut, "control-command")
        XCTAssertEqual(decoded.privacyRevealLockShortcut, "control-shift-r")
        XCTAssertEqual(decoded.privacyCurtainMode, .spotlight)
        XCTAssertEqual(decoded.privacyCurtainScope, .fullScreen)
        XCTAssertEqual(decoded.privacyCurtainIntensity, 0.72, accuracy: 0.0001)
        XCTAssertEqual(decoded.privacyCurtainSpotlightRadius, 240, accuracy: 0.0001)
        XCTAssertEqual(decoded.privacyCurtainSpotlightShape, .ellipse)
    }
}
