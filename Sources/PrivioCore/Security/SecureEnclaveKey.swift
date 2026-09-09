import Foundation
import Security
import LocalAuthentication

/// Klucz podpisujący w Secure Enclave (sekcja 12).
///
/// Sam klucz nigdy nie opuszcza Enclave. Udane podpisanie wyzwania jest
/// kryptograficznym dowodem obecności użytkownika (biometria/hasło), dzięki czemu
/// autoryzacja jest „znacząca", a nie tylko boolem w pamięci. Na Macach bez
/// Secure Enclave operacje zwracają nil - wtedy polegamy na wyniku
/// LocalAuthentication (bez fałszywego bezpieczeństwa).
enum SecureEnclaveKey {
    /// WHY: stały tag identyfikuje jedyny klucz podpisujący Privio w Keychain.
    private static let tag = "com.privio.auth.signing".data(using: .utf8)!

    /// Wczytuje istniejący klucz, reużywając uwierzytelnionego kontekstu
    /// (bez ponownego promptu w oknie reużycia).
    private static func loadKey(context: LAContext) -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
            kSecUseAuthenticationContext as String: context,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let item else { return nil }
        return (item as! SecKey)
    }

    /// Tworzy trwały klucz EC w Secure Enclave chroniony obecnością użytkownika
    /// (biometria lub hasło). Zwraca nil, gdy SE niedostępne.
    private static func createKey() -> SecKey? {
        var acError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .userPresence],
            &acError) else {
            PrivioLog.auth.error("SecAccessControl błąd")
            return nil
        }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag,
                kSecAttrAccessControl as String: access,
            ],
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            PrivioLog.auth.notice("Secure Enclave niedostępne lub błąd klucza - polegamy na LocalAuthentication")
            return nil
        }
        return key
    }

    /// Podpisuje wyzwanie kluczem z Enclave. Zwraca podpis lub nil (brak SE).
    static func sign(_ challenge: Data, context: LAContext) -> Data? {
        let key = loadKey(context: context) ?? createKey()
        guard let key else { return nil }
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key, .ecdsaSignatureMessageX962SHA256, challenge as CFData, &error) else {
            PrivioLog.auth.error("Podpis SE nieudany")
            return nil
        }
        return signature as Data
    }
}
