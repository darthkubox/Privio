import XCTest
import CryptoKit
@testable import PrivioCore

final class LicenseTests: XCTestCase {

    /// Tworzy weryfikator dopasowany do świeżej pary kluczy + funkcję podpisującą.
    private func keyed() -> (LicenseVerifier, (LicensePayload) -> String) {
        let priv = Curve25519.Signing.PrivateKey()
        let verifier = LicenseVerifier(publicKeyBase64: priv.publicKey.rawRepresentation.base64EncodedString())
        func sign(_ payload: LicensePayload) -> String {
            let data = try! JSONEncoder().encode(payload)
            let sig = try! priv.signature(for: data)
            return data.base64URLEncodedString + "." + sig.base64URLEncodedString
        }
        return (verifier, sign)
    }

    private func proPayload(_ id: String = "ABC123") -> LicensePayload {
        LicensePayload(licenseID: id, issuedAt: "2026-08-30")
    }

    func testValidLicenseVerifies() {
        let (v, sign) = keyed()
        XCTAssertEqual(v.verify(sign(proPayload()))?.licenseID, "ABC123")
    }

    /// Podmienia znak w ŚRODKU (nie na końcu - ostatni znak base64url ma bity
    /// paddingu, które mogą nie zmienić zdekodowanych bajtów).
    private func tamperMiddle(_ s: String) -> String {
        var chars = Array(s)
        let i = chars.count / 2
        chars[i] = chars[i] == "A" ? "B" : "A"
        return String(chars)
    }

    func testTamperedPayloadFails() {
        let (v, sign) = keyed()
        var parts = sign(proPayload()).split(separator: ".").map(String.init)
        parts[0] = tamperMiddle(parts[0])
        XCTAssertNil(v.verify(parts.joined(separator: ".")))   // podpis nie pasuje do zmienionego ładunku
    }

    func testTamperedSignatureFails() {
        let (v, sign) = keyed()
        var parts = sign(proPayload()).split(separator: ".").map(String.init)
        parts[1] = tamperMiddle(parts[1])
        XCTAssertNil(v.verify(parts.joined(separator: ".")))
    }

    func testWrongKeyFails() {
        let (_, sign) = keyed()
        let other = LicenseVerifier(
            publicKeyBase64: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString())
        XCTAssertNil(other.verify(sign(proPayload())))
    }

    func testMalformedFails() {
        let v = LicenseVerifier()
        XCTAssertNil(v.verify("not-a-license"))
        XCTAssertNil(v.verify(""))
        XCTAssertNil(v.verify("a.b.c"))
    }

    func testWrongEditionOrProductRejected() {
        let (v, sign) = keyed()
        let free = sign(LicensePayload(edition: "free", licenseID: "F", issuedAt: "2026-08-30"))
        XCTAssertNil(v.verify(free))                 // poprawny podpis, ale edycja != pro
        let wrongProduct = sign(LicensePayload(product: "other", licenseID: "P", issuedAt: "2026-08-30"))
        XCTAssertNil(v.verify(wrongProduct))
    }

    func testManagerActivateAndEdition() {
        let (v, sign) = keyed()
        let manager = LicenseManager(verifier: v, store: InMemoryLicenseStore())
        XCTAssertEqual(manager.currentEdition(), .free)
        XCTAssertEqual(manager.activate(sign(proPayload("ABC"))), .activated(licenseID: "ABC"))
        XCTAssertEqual(manager.currentEdition(), .pro)
        XCTAssertTrue(manager.isPro)
        manager.deactivate()
        XCTAssertEqual(manager.currentEdition(), .free)
    }

    func testManagerRejectsInvalid() {
        let manager = LicenseManager(verifier: LicenseVerifier(), store: InMemoryLicenseStore())
        XCTAssertEqual(manager.activate("garbage"), .invalid)
        XCTAssertEqual(manager.currentEdition(), .free)
    }
}
