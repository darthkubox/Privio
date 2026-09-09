import Foundation
import CryptoKit
import Security

/// Integralność konfiguracji (sekcja 13): HMAC‑SHA256 nad `config.json` kluczem
/// trzymanym w Keychain. Ktoś edytujący plik ręcznie nie zna klucza HMAC, więc
/// manipulacja zostanie wykryta. NIE blokujemy użytkownika - jedynie sygnalizujemy
/// naruszenie i preferujemy bezpieczne (nieosłabione) zachowanie.
enum ConfigIntegrity {
    private static let service = "com.privio.Privio.integrity"
    private static let account = "config-hmac-key"

    /// Istniejący klucz HMAC z Keychain (nil, jeśli brak / niedostępny).
    private static func existingKey() -> SymmetricKey? {
        loadKeyData().map(SymmetricKey.init(data:))
    }

    /// Klucz do ZAPISU tagu - tworzony przy pierwszym użyciu.
    private static func keyOrCreate() -> SymmetricKey {
        if let existing = existingKey() { return existing }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let data = Data(bytes)
        saveKeyData(data)
        return SymmetricKey(data: data)
    }

    static func tag(for data: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: keyOrCreate()))
    }

    /// Zwraca `false` (naruszenie) TYLKO gdy klucz jest dostępny, a tag nie pasuje.
    /// Gdy klucza nie da się odczytać (np. podpis ad‑hoc po przebudowie), nie
    /// potrafimy zweryfikować - NIE alarmujemy fałszywie.
    static func isValid(_ data: Data, tag: Data) -> Bool {
        guard let key = existingKey() else { return true }
        return HMAC<SHA256>.isValidAuthenticationCode(tag, authenticating: data, using: key)
    }

    // MARK: - Keychain klucza

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func loadKeyData() -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func saveKeyData(_ data: Data) {
        SecItemDelete(baseQuery as CFDictionary)
        var attrs = baseQuery
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attrs as CFDictionary, nil)
    }
}
