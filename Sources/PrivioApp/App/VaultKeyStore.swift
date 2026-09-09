import Foundation
import LocalAuthentication
import Security

/// Przechowuje hasło obrazu sejfu w systemowym Pęku kluczy.
///
/// Dane są dostępne wyłącznie na tym Macu i każde odczytanie wymaga
/// potwierdzenia obecności użytkownika (Touch ID / Apple Watch / hasło konta).
/// Privio nigdy nie przechowuje ani nie otrzymuje hasła konta macOS.
struct VaultKeyStore: @unchecked Sendable {
    enum KeyStoreError: LocalizedError {
        case accessControl(String)
        case authentication(String)
        case security(OSStatus)
        case invalidData

        var errorDescription: String? {
            switch self {
            case .accessControl(let message): return message
            case .authentication(let message): return message
            case .security(let status):
                return SecCopyErrorMessageString(status, nil) as String?
                    ?? "Keychain error (\(status))"
            case .invalidData: return "The vault key stored in Keychain is invalid."
            }
        }
    }

    private let service = "com.privio.Privio.private-vault"
    private let fallbackService = "com.privio.Privio.private-vault.local-build"
    private let account = "disk-image-password"

    func containsKey() -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        var query = protectedBase
        query.merge([
            kSecReturnData as String: false,
            kSecUseAuthenticationContext as String: context
        ]) { _, new in new }
        let protectedStatus = SecItemCopyMatching(query as CFDictionary, nil)
        if protectedStatus == errSecSuccess || protectedStatus == errSecInteractionNotAllowed {
            return true
        }

        var fallbackQuery = fallbackBase
        fallbackQuery[kSecReturnData as String] = false
        let fallbackStatus = SecItemCopyMatching(fallbackQuery as CFDictionary, nil)
        return fallbackStatus == errSecSuccess || fallbackStatus == errSecInteractionNotAllowed
    }

    func store(_ password: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            var accessError: Unmanaged<CFError>?
            guard let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                .userPresence,
                &accessError
            ) else {
                throw KeyStoreError.accessControl(
                    accessError?.takeRetainedValue().localizedDescription
                        ?? "Unable to protect the vault key."
                )
            }

            let base = protectedBase
            SecItemDelete(base as CFDictionary)

            var item = base
            item[kSecAttrAccessControl as String] = access
            item[kSecValueData as String] = Data(password.utf8)
            item[kSecAttrLabel as String] = "Privio Private Vault"
            let status = SecItemAdd(item as CFDictionary, nil)
            if status == errSecMissingEntitlement {
                // Lokalne paczki testowe są podpisane ad-hoc i nie mają profilu
                // zawierającego application-identifier. macOS odrzuca wtedy
                // Data Protection Keychain. Sekret nadal trafia do systemowego
                // Pęku kluczy, a odczyt jest poprzedzany pełnym LocalAuthentication.
                try storeFallback(password)
                return
            }
            guard status == errSecSuccess else { throw KeyStoreError.security(status) }
            SecItemDelete(fallbackBase as CFDictionary)
        }.value
    }

    func read(reason: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let context = LAContext()
            context.touchIDAuthenticationAllowableReuseDuration = 0
            context.localizedCancelTitle = NSLocalizedString("Cancel", comment: "Cancel vault authentication")
            context.localizedReason = reason

            var query = protectedBase
            query.merge([
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecUseAuthenticationContext as String: context
            ]) { _, new in new }
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecSuccess {
                return try password(from: result)
            }
            guard status == errSecItemNotFound || status == errSecMissingEntitlement else {
                throw KeyStoreError.security(status)
            }

            return try await readFallback(reason: reason)
        }.value
    }

    func remove() {
        SecItemDelete(protectedBase as CFDictionary)
        SecItemDelete(fallbackBase as CFDictionary)
    }

    private var protectedBase: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    private var fallbackBase: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: fallbackService,
            kSecAttrAccount as String: account
        ]
    }

    private func storeFallback(_ password: String) throws {
        let base = fallbackBase
        SecItemDelete(base as CFDictionary)
        var item = base
        item[kSecValueData as String] = Data(password.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        item[kSecAttrLabel as String] = "Privio Private Vault (local build)"
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeyStoreError.security(status) }
    }

    private func readFallback(reason: String) async throws -> String {
        var existenceQuery = fallbackBase
        existenceQuery[kSecReturnData as String] = false
        let existenceStatus = SecItemCopyMatching(existenceQuery as CFDictionary, nil)
        guard existenceStatus == errSecSuccess || existenceStatus == errSecInteractionNotAllowed else {
            throw KeyStoreError.security(existenceStatus)
        }

        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = 0
        context.localizedCancelTitle = NSLocalizedString("Cancel", comment: "Cancel vault authentication")
        var availabilityError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &availabilityError) else {
            throw KeyStoreError.authentication(
                availabilityError?.localizedDescription
                    ?? NSLocalizedString("Touch ID or the Mac password is unavailable.", comment: "Vault auth unavailable")
            )
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: KeyStoreError.authentication(
                        error?.localizedDescription
                            ?? NSLocalizedString("Authentication failed.", comment: "Vault auth failure")
                    ))
                }
            }
        }

        var query = fallbackBase
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { throw KeyStoreError.security(status) }
        return try password(from: result)
    }

    private func password(from result: CFTypeRef?) throws -> String {
        guard let data = result as? Data,
              let password = String(data: data, encoding: .utf8),
              !password.isEmpty else { throw KeyStoreError.invalidData }
        return password
    }
}
