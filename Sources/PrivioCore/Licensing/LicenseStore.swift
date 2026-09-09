import Foundation
import Security

/// Przechowywanie licencji (do podmiany w testach). Sama licencja nie jest tajna -
/// autentyczność daje podpis - ale trzymamy ją w Keychain (bezpiecznie, przeżywa
/// reinstalację/aktualizację).
public protocol LicenseStoring: Sendable {
    func load() -> String?
    func save(_ license: String)
    func clear()
}

/// Keychain (generic password). Bez sieci, bez kont.
public struct KeychainLicenseStore: LicenseStoring {
    private let service = "com.privio.Privio.license"
    private let account = "pro-license"

    public init() {}

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ license: String) {
        SecItemDelete(baseQuery as CFDictionary)
        var attrs = baseQuery
        attrs[kSecValueData as String] = Data(license.utf8)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attrs as CFDictionary, nil)
    }

    public func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

/// Magazyn licencji w pliku (`~/Library/Application Support/Privio/license.txt`).
///
/// Licencja NIE jest tajna - jej autentyczność daje podpis Ed25519, więc plik jest
/// bezpiecznym i wystarczającym magazynem. Świadomie wybieramy plik zamiast Keychain,
/// bo pod podpisem ad‑hoc Keychain przy każdym przebudowaniu żąda hasła do pęku kluczy
/// (inny podpis kodu = brak dostępu do wcześniej zapisanego elementu). Plik jest
/// usuwany przy deinstalacji razem z całym katalogiem `Privio/`.
public struct FileLicenseStore: LicenseStoring {
    private let fileURL: URL

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Privio", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("license.txt")
    }

    public func load() -> String? {
        guard let s = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func save(_ license: String) {
        let data = Data(license.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        try? data.write(to: fileURL, options: [.atomic])
    }

    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// Prosty magazyn w pamięci - do testów.
public final class InMemoryLicenseStore: LicenseStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    public init(_ initial: String? = nil) { value = initial }
    public func load() -> String? { lock.lock(); defer { lock.unlock() }; return value }
    public func save(_ license: String) { lock.lock(); value = license; lock.unlock() }
    public func clear() { lock.lock(); value = nil; lock.unlock() }
}
