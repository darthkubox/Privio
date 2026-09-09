import CryptoKit
import Foundation
import Security

struct PrivioBeaconPairing: Sendable, Hashable {
    let id: String
    let secret: Data
    let deviceName: String?
    var deviceID: String { "ble:privio:\(id)" }
}

enum PrivioBeaconPairingError: LocalizedError {
    case invalidCode
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidCode: return String(localized: "This Privio Watch pairing code is invalid.")
        case .keychain(let status): return "Keychain error (\(status))."
        }
    }
}

/// Sekrety zegarków nigdy nie trafiają do config.json. Są trzymane jako generic
/// passwords w systemowym Pęku kluczy i używane tylko do weryfikacji rotujących tokenów BLE.
final class PrivioBeaconPairingStore: @unchecked Sendable {
    static let shared = PrivioBeaconPairingStore()
    private let service = "com.privio.beacon-pairing.v2"
    private let namesKey = "privio.beacon.customNames"
    private let lock = NSLock()
    private var cache: [String: Data] = [:]

    /// Trwały fallback plikowy (0600). Keychain przy samopodpisanym, lokalnym
    /// buildzie wiąże ACL z cdhash, więc każda aktualizacja Privio zrywałaby
    /// parowanie (`pairings=0`) - a beacon musi działać po aktualizacjach. Sekret
    /// wyłącznie WERYFIKUJE token obecności (wyzwala blokadę), nigdy nie odblokowuje,
    /// więc plik o prawach 0600 to akceptowalny kompromis. Keychain zostaje jako
    /// preferowane źródło dla przyszłych podpisanych (Developer ID) buildów.
    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Privio", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("beacon-pairings.json")
    }

    private init() { reload() }

    func all() -> [PrivioBeaconPairing] {
        lock.withLock { cache.map { PrivioBeaconPairing(id: $0.key, secret: $0.value, deviceName: nil) } }
    }

    func pairing(for deviceID: String) -> PrivioBeaconPairing? {
        guard let id = Self.pairingID(from: deviceID) else { return nil }
        return lock.withLock { cache[id].map { PrivioBeaconPairing(id: id, secret: $0, deviceName: nil) } }
    }

    func displayName(for deviceID: String) -> String? {
        guard let id = Self.pairingID(from: deviceID) else { return nil }
        return (UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String])?[id]
    }

    func setDisplayName(_ name: String, for deviceID: String) {
        guard let id = Self.pairingID(from: deviceID) else { return }
        var names = (UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String]) ?? [:]
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { names.removeValue(forKey: id) } else { names[id] = String(trimmed.prefix(40)) }
        UserDefaults.standard.set(names, forKey: namesKey)
    }

    func setDeviceProvidedName(_ name: String, for deviceID: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let base = trimmed.replacingOccurrences(of: #"\s*\(PrivioWear\)\s*$"#,
                                                 with: "", options: [.regularExpression, .caseInsensitive])
        setDisplayName("\(String(base.prefix(60))) (PrivioWear)", for: deviceID)
    }

    func save(pairingText: String) throws -> PrivioBeaconPairing {
        let pairing = try Self.parse(pairingText)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: pairing.id
        ]
        SecItemDelete(base as CFDictionary)
        var item = base
        item[kSecValueData as String] = pairing.secret
        // Otwarty ACL: bez tego wpis jest związany z podpisem aplikacji, która go
        // utworzyła; po aktualizacji Privio tło skanera nie odczyta go w trybie
        // nieinteraktywnym (pairings=0). Fallback do zwykłej dostępności, gdyby ACL
        // się nie utworzył. Sekret beacona wyłącznie WYZWALA blokadę, nigdy nie odblokowuje.
        if let access = Self.openAccess() {
            item[kSecAttrAccess as String] = access
        } else {
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
        _ = SecItemAdd(item as CFDictionary, nil)   // best-effort; plik jest trwałym źródłem
        lock.withLock { cache[pairing.id] = pairing.secret }
        if let name = pairing.deviceName { setDeviceProvidedName(name, for: pairing.deviceID) }
        persistFile()
        return pairing
    }

    /// ACL „dostęp dla wszystkich aplikacji bez pytania" dla wpisu w pliku Pęku kluczy.
    private static func openAccess() -> SecAccess? {
        var access: SecAccess?
        guard SecAccessCreate("Privio Watch pairing" as CFString, nil, &access) == errSecSuccess,
              let access else { return nil }
        var aclsRef: CFArray?
        guard SecAccessCopyACLList(access, &aclsRef) == errSecSuccess,
              let acls = aclsRef as? [SecACL] else { return access }
        for acl in acls {
            // nil lista aplikacji ⇒ każda aplikacja ma dostęp bez promptu.
            SecACLSetContents(acl, nil, "Privio Watch pairing" as CFString, [])
        }
        return access
    }

    func remove(deviceID: String) {
        guard let id = deviceID.split(separator: ":").last.map(String.init) else { return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: id]
        SecItemDelete(query as CFDictionary)
        _ = lock.withLock { cache.removeValue(forKey: id) }
        var names = (UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String]) ?? [:]
        names.removeValue(forKey: id)
        UserDefaults.standard.set(names, forKey: namesKey)
        persistFile()
    }

    private static func pairingID(from deviceID: String) -> String? {
        guard deviceID.hasPrefix("ble:privio:"),
              let id = deviceID.split(separator: ":").last.map(String.init),
              id.count == 16 else { return nil }
        return id
    }

    private func reload() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        var loaded: [String: Data] = [:]
        if status == errSecSuccess, let rows = result as? [[String: Any]] {
            for row in rows {
                if let id = row[kSecAttrAccount as String] as? String,
                   let data = row[kSecValueData as String] as? Data { loaded[id] = data }
            }
        } else if status != errSecItemNotFound {
        }
        // Plik jest trwałym źródłem (przeżywa aktualizacje). Uzupełnia to, czego
        // Keychain nie oddał, a gdy Keychain miał wpis brakujący w pliku - dosyp go
        // do pliku, żeby utrwalić parowania sprzed tej zmiany.
        let fromFile = Self.loadFile()
        for (id, secret) in fromFile where loaded[id] == nil { loaded[id] = secret }
        lock.withLock { cache = loaded }
        if loaded.count > fromFile.count { persistFile() }   // utrwal wpisy tylko-z-Keychain
    }

    private func persistFile() {
        let snapshot = lock.withLock { cache }
        let hex = snapshot.mapValues { $0.map { String(format: "%02x", $0) }.joined() }
        guard let data = try? JSONSerialization.data(withJSONObject: hex) else { return }
        let url = Self.fileURL
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func loadFile() -> [String: Data] {
        guard let data = try? Data(contentsOf: fileURL),
              let hex = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        var out: [String: Data] = [:]
        for (id, value) in hex {
            let bytes = stride(from: 0, to: value.count, by: 2).compactMap { i -> UInt8? in
                let s = value.index(value.startIndex, offsetBy: i)
                let e = value.index(s, offsetBy: 2, limitedBy: value.endIndex) ?? value.endIndex
                return UInt8(value[s..<e], radix: 16)
            }
            if bytes.count == 16 { out[id] = Data(bytes) }
        }
        return out
    }

    static func parse(_ input: String) throws -> PrivioBeaconPairing {
        let compact = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret: Data
        if let components = URLComponents(string: compact), components.scheme == "privio",
           components.host == "pair",
           components.queryItems?.first(where: { $0.name == "v" })?.value == "2",
           let encoded = components.queryItems?.first(where: { $0.name == "s" })?.value,
           let decoded = Data(base64URLEncoded: encoded) {
            secret = decoded
        } else if let decoded = Data(base32Encoded: compact) {
            secret = decoded
        } else {
            throw PrivioBeaconPairingError.invalidCode
        }
        guard secret.count == 16 else { throw PrivioBeaconPairingError.invalidCode }
        let id = SHA256.hash(data: secret).prefix(8).map { String(format: "%02X", $0) }.joined()
        if let components = URLComponents(string: compact), components.scheme == "privio",
           let claimed = components.queryItems?.first(where: { $0.name == "id" })?.value,
           claimed.uppercased() != id { throw PrivioBeaconPairingError.invalidCode }
        let providedName: String?
        if let components = URLComponents(string: compact), components.scheme == "privio" {
            providedName = components.queryItems?.first(where: { $0.name == "n" })?.value
        } else {
            providedName = nil
        }
        return PrivioBeaconPairing(id: id, secret: secret, deviceName: providedName)
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var normalized = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        normalized += String(repeating: "=", count: (4 - normalized.count % 4) % 4)
        self.init(base64Encoded: normalized)
    }

    init?(base32Encoded value: String) {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        let cleaned = value.uppercased().filter { $0 != "-" && !$0.isWhitespace }
        guard cleaned.count == 26 else { return nil }
        var output = Data(), buffer = 0, bits = 0
        for character in cleaned {
            guard let index = alphabet.firstIndex(of: character) else { return nil }
            buffer = (buffer << 5) | index
            bits += 5
            if bits >= 8 {
                output.append(UInt8((buffer >> (bits - 8)) & 0xff))
                bits -= 8
                buffer &= bits == 0 ? 0 : (1 << bits) - 1
            }
        }
        self = output
    }
}
