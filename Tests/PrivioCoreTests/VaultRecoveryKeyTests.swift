import XCTest
@testable import PrivioCore

final class VaultRecoveryKeyTests: XCTestCase {
    private let key = "00112233445566778899AABBCCDDEEFF00112233445566778899AABBCCDDEEFF"

    func testDisplayGroupsKeyWithoutChangingIt() {
        let displayed = VaultRecoveryKey.display(key)
        XCTAssertEqual(displayed.split(separator: "-").count, 16)
        XCTAssertEqual(VaultRecoveryKey.normalize(displayed), key)
    }

    func testNormalizeAcceptsLowercaseSpacesAndHyphens() {
        let input = "0011 2233-4455 6677 8899 aabb ccdd eeff 0011 2233 4455 6677 8899 aabb ccdd eeff"
        XCTAssertEqual(VaultRecoveryKey.normalize(input), key)
        XCTAssertTrue(VaultRecoveryKey.isValid(input))
    }

    func testRejectsWrongLengthAndNonASCIILookalikes() {
        XCTAssertFalse(VaultRecoveryKey.isValid(String(key.dropLast())))
        XCTAssertFalse(VaultRecoveryKey.isValid(key + "0"))
        XCTAssertFalse(VaultRecoveryKey.isValid(String(repeating: "Ｆ", count: 64)))
    }

    func testGenerateProducesValidUppercaseHexKeys() {
        var seen = Set<String>()
        for _ in 0..<64 {
            let generated = VaultRecoveryKey.generate()
            XCTAssertEqual(generated.count, VaultRecoveryKey.normalizedLength)
            XCTAssertTrue(VaultRecoveryKey.isValid(generated))
            // Wygenerowany klucz jest już znormalizowany (wielkie hex, bez separatorów).
            XCTAssertEqual(VaultRecoveryKey.normalize(generated), generated)
            seen.insert(generated)
        }
        // Kryptograficzne źródło nie może zwracać powtórzeń na tak małej próbce.
        XCTAssertEqual(seen.count, 64)
    }
}
