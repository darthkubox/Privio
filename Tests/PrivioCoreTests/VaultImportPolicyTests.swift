import XCTest
@testable import PrivioCore

final class VaultImportPolicyTests: XCTestCase {
    private let image = URL(fileURLWithPath: "/Users/me/Library/Application Support/Privio Vault/Privio Vault.sparsebundle")

    private func rejection(source: String, isSymlink: Bool = false) -> VaultImportPolicy.Rejection? {
        VaultImportPolicy.rejection(
            canonicalSource: URL(fileURLWithPath: source),
            canonicalImage: image,
            isSymbolicLink: isSymlink
        )
    }

    func testAllowsOrdinaryFile() {
        XCTAssertNil(rejection(source: "/Users/me/Documents/passport.pdf"))
    }

    func testRejectsSymbolicLink() {
        XCTAssertEqual(rejection(source: "/Users/me/Documents/alias.pdf", isSymlink: true), .symbolicLink)
    }

    func testRejectsTheVaultImageItself() {
        XCTAssertEqual(rejection(source: image.path), .vaultImageItself)
    }

    func testRejectsAnythingInsideTheVaultImage() {
        // Sparsebundle to katalog z pasmami danych - nie wolno importować jego wnętrza.
        XCTAssertEqual(rejection(source: image.appendingPathComponent("bands/0a").path), .insideVaultImage)
        XCTAssertEqual(rejection(source: image.appendingPathComponent("token.plist").path), .insideVaultImage)
    }

    func testDoesNotOverBlockSiblingsSharingAPrefix() {
        // Granica ścieżki jest po komponencie: sąsiad o podobnej nazwie jest dozwolony.
        XCTAssertNil(rejection(source: image.path + "-backup"))
        XCTAssertNil(rejection(source: "/Users/me/Library/Application Support/Privio Vault/notes.txt"))
    }

    // MARK: - Unikalna nazwa docelowa

    func testKeepsOriginalNameWhenFree() {
        let name = VaultImportPolicy.uniqueDestinationName(
            for: URL(fileURLWithPath: "/x/report.pdf"),
            exists: { _ in false }
        )
        XCTAssertEqual(name, "report.pdf")
    }

    func testAppendsSuffixPreservingExtension() {
        let taken: Set<String> = ["report.pdf"]
        let name = VaultImportPolicy.uniqueDestinationName(
            for: URL(fileURLWithPath: "/x/report.pdf"),
            exists: { taken.contains($0) }
        )
        XCTAssertEqual(name, "report 2.pdf")
    }

    func testSkipsAlreadyTakenSuffixes() {
        let taken: Set<String> = ["report.pdf", "report 2.pdf", "report 3.pdf"]
        let name = VaultImportPolicy.uniqueDestinationName(
            for: URL(fileURLWithPath: "/x/report.pdf"),
            exists: { taken.contains($0) }
        )
        XCTAssertEqual(name, "report 4.pdf")
    }

    func testHandlesNamesWithoutExtension() {
        let taken: Set<String> = ["Archive"]
        let name = VaultImportPolicy.uniqueDestinationName(
            for: URL(fileURLWithPath: "/x/Archive"),
            exists: { taken.contains($0) }
        )
        XCTAssertEqual(name, "Archive 2")
    }
}
