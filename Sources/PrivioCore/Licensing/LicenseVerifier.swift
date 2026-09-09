import Foundation
import CryptoKit

/// Weryfikacja licencji Pro WYŁĄCZNIE lokalnie, kluczem publicznym (Ed25519 /
/// Curve25519). Klucz prywatny nigdy nie trafia do repo/apki. Nawet mając klucz
/// publiczny nie da się wygenerować ważnej licencji. Zero komunikacji sieciowej.
///
/// Format licencji (ASCII, do wklejenia): `base64url(payloadJSON).base64url(signature)`.
public struct LicenseVerifier: Sendable {
    /// Klucz publiczny wbudowany w Privio (odpowiadający kluczowi prywatnemu wydawcy).
    public static let embeddedPublicKeyBase64 = "SOrOsc1nJoDo6FSNaBVKcbojunCwLlsVhxy76i0NsmI="

    private let publicKey: Curve25519.Signing.PublicKey
    private let supportedSchema = 1

    /// - Parameter publicKeyBase64: domyślnie klucz wbudowany; testy wstrzykują własny.
    public init(publicKeyBase64: String = LicenseVerifier.embeddedPublicKeyBase64) {
        // Wbudowany klucz jest stały i poprawny; w razie błędu użyj pustego klucza,
        // który nie zweryfikuje żadnej licencji (Free), zamiast crashować.
        if let data = Data(base64Encoded: publicKeyBase64),
           let key = try? Curve25519.Signing.PublicKey(rawRepresentation: data) {
            self.publicKey = key
        } else {
            self.publicKey = Curve25519.Signing.PrivateKey().publicKey  // nikt nie zna klucza prywatnego
        }
    }

    /// Weryfikuje łańcuch licencji i zwraca ładunek, jeśli podpis i pola są poprawne.
    public func verify(_ licenseString: String) -> LicensePayload? {
        let trimmed = licenseString.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let payloadData = Data(base64URLEncoded: String(parts[0])),
              let signature = Data(base64URLEncoded: String(parts[1])) else { return nil }

        // Autentyczność: podpis nad DOKŁADNYMI bajtami ładunku.
        guard publicKey.isValidSignature(signature, for: payloadData) else { return nil }

        guard let payload = try? JSONDecoder().decode(LicensePayload.self, from: payloadData),
              payload.product == "privio",
              payload.edition == "pro",
              payload.schema == supportedSchema else { return nil }
        return payload
    }
}

extension Data {
    /// base64url (RFC 4648 §5, bez paddingu) → Data.
    init?(base64URLEncoded string: String) {
        var s = string.replacingOccurrences(of: "-", with: "+")
                      .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        guard let data = Data(base64Encoded: s) else { return nil }
        self = data
    }

    /// Data → base64url (bez paddingu).
    var base64URLEncodedString: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
