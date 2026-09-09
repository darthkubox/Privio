import Foundation
import Security

/// Format klucza odzyskiwania sejfu: 256 bitów zapisanych jako 64 cyfry hex.
/// Myślniki i odstępy są wyłącznie prezentacyjne.
public enum VaultRecoveryKey {
    /// Długość znormalizowanego klucza (256 bitów = 64 cyfry hex).
    public static let normalizedLength = 64

    /// Losuje nowy klucz odzyskiwania z kryptograficznego źródła systemowego.
    /// Zwracana wartość jest zawsze poprawnym kluczem (`isValid == true`).
    public static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        precondition(SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess)
        return bytes.map { String(format: "%02X", $0) }.joined()
    }

    public static func normalize(_ value: String) -> String {
        value.uppercased().filter { $0.isASCII && $0.isHexDigit }
    }

    public static func isValid(_ value: String) -> Bool {
        normalize(value).count == normalizedLength
    }

    public static func display(_ value: String) -> String {
        let normalized = normalize(value)
        return stride(from: 0, to: normalized.count, by: 4).map { offset in
            let start = normalized.index(normalized.startIndex, offsetBy: offset)
            let end = normalized.index(start, offsetBy: min(4, normalized.count - offset))
            return String(normalized[start..<end])
        }.joined(separator: "-")
    }
}
