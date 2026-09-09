import Foundation

/// Edycja Privio. Domyślnie Free - Pro odblokowuje podpisana licencja.
public enum Edition: String, Codable, Sendable, Equatable {
    case free
    case pro
}

/// Ładunek licencji (podpisywany kluczem prywatnym wydawcy). Celowo NIE zawiera
/// identyfikatorów sprzętu, nazwy użytkownika, listy chronionych apek ani innych
/// danych osobowych (zgodnie z LICENSING_ARCHITECTURE).
public struct LicensePayload: Codable, Sendable, Equatable {
    public var schema: Int
    public var product: String
    public var edition: String
    public var licenseID: String
    public var issuedAt: String

    enum CodingKeys: String, CodingKey {
        case schema, product, edition
        case licenseID = "license_id"
        case issuedAt = "issued_at"
    }

    public init(schema: Int = 1, product: String = "privio", edition: String = "pro",
                licenseID: String, issuedAt: String) {
        self.schema = schema
        self.product = product
        self.edition = edition
        self.licenseID = licenseID
        self.issuedAt = issuedAt
    }
}
