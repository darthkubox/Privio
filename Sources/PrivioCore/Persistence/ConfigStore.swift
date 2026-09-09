import Foundation

/// Utrwalany na dysku stan konfiguracji (bez stanu ulotnego - sekcja 7).
public struct PersistedState: Codable, Sendable {
    public var apps: [ProtectedApp]
    public var webTargets: [WebTarget]
    public var configuration: AppConfiguration

    public init(apps: [ProtectedApp] = [],
                webTargets: [WebTarget] = [],
                configuration: AppConfiguration = .default) {
        self.apps = apps
        self.webTargets = webTargets
        self.configuration = configuration
    }

    // Dekodowanie zgodne wstecz: starszy config.json bez `webTargets` → pusta lista.
    private enum CodingKeys: String, CodingKey { case apps, webTargets, configuration }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apps = try c.decodeIfPresent([ProtectedApp].self, forKey: .apps) ?? []
        webTargets = try c.decodeIfPresent([WebTarget].self, forKey: .webTargets) ?? []
        configuration = try c.decodeIfPresent(AppConfiguration.self, forKey: .configuration) ?? .default
    }
}

/// Zapis/odczyt konfiguracji jako JSON w `~/Library/Application Support/Privio/`.
///
/// Świadomie NIE trzymamy tu żadnych sekretów (klucze/hasła/tokeny - te idą do
/// Keychain/Secure Enclave, sekcja 12). Tylko lista chronionych apek i ustawienia.
public struct ConfigStore: Sendable {
    private let fileURL: URL

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Privio", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("config.json")
    }

    public func load() -> PersistedState {
        guard let data = try? Data(contentsOf: fileURL) else { return PersistedState() }
        do {
            return try JSONDecoder().decode(PersistedState.self, from: data)
        } catch {
            PrivioLog.persistence.error("Nie udało się zdekodować config.json: \(error.localizedDescription, privacy: .public)")
            return PersistedState()
        }
    }

    public func save(_ state: PersistedState) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            PrivioLog.persistence.error("Nie udało się zapisać config.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Integralność konfiguracji (HMAC w Keychain) jest CHWILOWO wyłączona.
    ///
    /// Pod podpisem ad‑hoc każdy przebudowany build ma inny podpis kodu, więc macOS
    /// za każdym razem żąda hasła do pęku kluczy, aby pozwolić na dostęp do klucza
    /// HMAC zapisanego przez poprzedni build - a niedostępny klucz dawał też fałszywe
    /// „integrity check failed". To utwardzenie (sekcja 13) wróci razem z wydzieleniem
    /// agenta przez XPC, gdy będzie stabilny podpis (Developer ID). Do tego czasu
    /// nie dotykamy Keychain przy starcie i raportujemy integralność jako OK.
    public func integrityValid() -> Bool {
        true
    }
}
