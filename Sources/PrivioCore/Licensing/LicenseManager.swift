import Foundation

/// Wynik próby aktywacji licencji.
public enum ActivationResult: Sendable, Equatable {
    case activated(licenseID: String)
    case invalid
}

/// Łączy weryfikator + magazyn: bieżąca edycja, aktywacja, dezaktywacja.
/// Wszystko lokalne - żadnej komunikacji sieciowej (sekcja Network Policy).
public struct LicenseManager: Sendable {
    private let verifier: LicenseVerifier
    private let store: LicenseStoring

    public init(verifier: LicenseVerifier = LicenseVerifier(),
                store: LicenseStoring = FileLicenseStore()) {
        self.verifier = verifier
        self.store = store
    }

    /// Edycja wyliczana z zapisanej, ZWERYFIKOWANEJ licencji.
    public func currentEdition() -> Edition {
        licenseInfo() == nil ? .free : .pro
    }

    public var isPro: Bool { currentEdition() == .pro }

    /// Zweryfikowany ładunek zapisanej licencji (lub nil).
    public func licenseInfo() -> LicensePayload? {
        guard let stored = store.load() else { return nil }
        return verifier.verify(stored)
    }

    /// Aktywacja = LOKALNA weryfikacja podpisu (nie aktywacja sieciowa).
    @discardableResult
    public func activate(_ key: String) -> ActivationResult {
        guard let payload = verifier.verify(key) else { return .invalid }
        store.save(key.trimmingCharacters(in: .whitespacesAndNewlines))
        return .activated(licenseID: payload.licenseID)
    }

    public func deactivate() {
        store.clear()
    }
}
