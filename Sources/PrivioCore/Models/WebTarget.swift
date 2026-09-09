import Foundation

/// Chroniona strona WWW (odpowiednik `ProtectedApp` dla adresów) - funkcja Pro.
///
/// Tożsamością główną jest znormalizowana **domena** (`example.com`), bez schematu
/// ani ścieżki - bo egzekwujemy blokadę na poziomie DNS/`/etc/hosts`, który operuje
/// nazwami hostów, nie ścieżkami. To WYŁĄCZNIE konfiguracja; stan ulotny (isLocked,
/// znaczniki czasu, tokeny) żyje w warstwie enforcement - jak przy aplikacjach.
public struct WebTarget: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID

    /// Znormalizowana domena bazowa, np. `example.com` (małe litery, bez `https://`,
    /// bez `www.`, bez ścieżki). Rozpoznajemy po niej cel.
    public var domain: String
    public var displayName: String
    public var protectionEnabled: Bool

    /// `/etc/hosts` nie wspiera wildcardów, więc „subdomeny" rozwijamy do konkretnych
    /// wpisów (apex + `www.`). Pełny wildcard `*.domena` wymaga filtra systemowego
    /// (NetworkExtension) - patrz Docs/Post-MVP.md.
    public var includeWWW: Bool

    /// Po odblokowaniu (auth) strona jest dostępna, po tylu sekundach bezczynności
    /// znów się blokuje. nil = zostaje odblokowana do końca sesji Privio.
    public var lockAfterInactivity: TimeInterval?

    public var requireTouchID: Bool
    public var allowPasswordFallback: Bool

    public init(
        id: UUID = UUID(),
        domain: String,
        displayName: String? = nil,
        protectionEnabled: Bool = true,
        includeWWW: Bool = true,
        lockAfterInactivity: TimeInterval? = 300,
        requireTouchID: Bool = true,
        allowPasswordFallback: Bool = true
    ) {
        self.id = id
        let normalized = WebTarget.normalize(domain)
        self.domain = normalized
        self.displayName = displayName ?? normalized
        self.protectionEnabled = protectionEnabled
        self.includeWWW = includeWWW
        self.lockAfterInactivity = lockAfterInactivity
        self.requireTouchID = requireTouchID
        self.allowPasswordFallback = allowPasswordFallback
    }

    /// Konkretne nazwy hostów wpisywane do `/etc/hosts`, gdy cel jest ZABLOKOWANY.
    public var blockedHostnames: [String] {
        var hosts = [domain]
        if includeWWW, !domain.hasPrefix("www.") { hosts.append("www.\(domain)") }
        return hosts
    }

    /// Sprowadza wpis użytkownika (URL/„https://www.x.com/panel"/„  X.COM ") do bazowej
    /// domeny `x.com`. Odporny na schemat, `www.`, ścieżkę, port i białe znaki.
    public static func normalize(_ input: String) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let range = s.range(of: "://") { s = String(s[range.upperBound...]) }
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }        // ścieżka
        if let at = s.lastIndex(of: "@") { s = String(s[s.index(after: at)...]) } // user:pass@
        if let colon = s.firstIndex(of: ":") { s = String(s[..<colon]) }        // port
        while s.hasPrefix("www.") { s = String(s.dropFirst(4)) }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    /// Czy `host` (np. z żądania/nawigacji) pasuje do tego celu (domena + subdomeny).
    public func matches(host: String) -> Bool {
        let h = WebTarget.normalize(host)
        return h == domain || h.hasSuffix("." + domain)
    }
}
