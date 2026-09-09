import Foundation
import Network

/// Lokalny proxy HTTP/HTTPS na wysokim porcie (bez roota). Przepuszcza cały ruch,
/// a przy próbie wejścia na ZABLOKOWANĄ domenę odmawia i zgłasza „trafienie"
/// (Privio prosi wtedy o Touch ID). Zestaw blokowanych domen jest aktualizowany
/// dynamicznie ze stanu enforcement. Nie odszyfrowuje TLS - host odczytuje z
/// żądania `CONNECT` (HTTPS) lub nagłówka `Host` (HTTP).
public final class WebProxyServer: @unchecked Sendable {
    public let port: UInt16
    private let queue = DispatchQueue(label: "com.privio.webproxy", attributes: .concurrent)
    private let lock = NSLock()
    private var _blocked: [String] = []
    private var _routed: [String] = []
    private var _configured: [String] = []
    private var _protectionEnabled = false
    private var _language = "en"
    private var _appVersion = ""
    private var _pausedUntil: Date?
    private var _extensions: [String: (version: String, lastSeen: Date)] = [:]
    private var listener: NWListener?
    private var onBlockedHit: (@Sendable (String) -> Void)?
    private var onLockRequest: (@Sendable (String) -> Void)?
    private var onActivity: (@Sendable (String, Bool) -> Void)?
    private var onOpenSettings: (@Sendable () -> Void)?
    private var onProtectRequest: (@Sendable (String) -> Void)?
    private var onRelockRequest: (@Sendable (String) -> Void)?
    private var onPauseRequest: (@Sendable (Int) -> Void)?
    private var onUnprotectRequest: (@Sendable (String) -> Void)?
    private var onResumeRequest: (@Sendable () -> Void)?

    /// Ścieżka, pod którą serwer wystawia plik PAC (system pobiera go po HTTP).
    public static let pacPath = "/privio.pac"

    public init(port: UInt16 = 8987) { self.port = port }

    /// Domeny (apex) aktualnie ZABLOKOWANE. Dopasowanie obejmuje subdomeny.
    public func updateBlockedDomains(_ domains: [String]) {
        lock.lock(); _blocked = domains.map { $0.lowercased() }; lock.unlock()
    }

    /// Domeny KIEROWANE przez proxy (chronione - dla treści PAC serwowanego po HTTP).
    public func updateRoutedDomains(_ domains: [String]) {
        lock.lock(); _routed = domains.map { $0.lowercased() }; lock.unlock()
    }

    public func updateConfiguredDomains(_ domains: [String]) {
        lock.lock(); _configured = domains.map { $0.lowercased() }; lock.unlock()
    }

    public func updateProtectionEnabled(_ enabled: Bool) {
        lock.lock(); _protectionEnabled = enabled; lock.unlock()
    }

    /// Kod języka aplikacji ("pl"/"en") - rozszerzenie w trybie „Auto" podąża za nim.
    public func updateLanguage(_ code: String) {
        lock.lock(); _language = code; lock.unlock()
    }

    /// Wersja aplikacji (short version) - pokazywana w UI rozszerzenia.
    public func updateAppVersion(_ version: String) {
        lock.lock(); _appVersion = version; lock.unlock()
    }

    /// Do kiedy ochrona jest wstrzymana (snooze). nil = nie wstrzymana.
    public func updatePausedUntil(_ date: Date?) {
        lock.lock(); _pausedUntil = date; lock.unlock()
    }

    private func routedSnapshot() -> [String] {
        lock.lock(); defer { lock.unlock() }; return _routed
    }

    private func configuredSnapshot() -> [String] {
        lock.lock(); defer { lock.unlock() }; return _configured
    }

    private func blockedSnapshot() -> [String] {
        lock.lock(); defer { lock.unlock() }; return _blocked
    }

    private func protectionEnabledSnapshot() -> Bool {
        lock.lock(); defer { lock.unlock() }; return _protectionEnabled
    }

    private func languageSnapshot() -> String {
        lock.lock(); defer { lock.unlock() }; return _language
    }

    private func appVersionSnapshot() -> String {
        lock.lock(); defer { lock.unlock() }; return _appVersion
    }

    private func pausedUntilSnapshot() -> Date? {
        lock.lock(); defer { lock.unlock() }; return _pausedUntil
    }

    /// Bieżący zestaw blokowanych domen (do wglądu/testów).
    public func currentBlockedDomains() -> [String] {
        lock.lock(); defer { lock.unlock() }; return _blocked
    }

    private func blockedMatch(_ host: String) -> String? {
        let h = host.lowercased()
        lock.lock(); defer { lock.unlock() }
        return _blocked.first { h == $0 || h.hasSuffix("." + $0) }
    }

    @discardableResult
    public func start(onBlockedHit: @escaping @Sendable (String) -> Void,
                      onLockRequest: (@Sendable (String) -> Void)? = nil,
                      onActivity: (@Sendable (String, Bool) -> Void)? = nil,
                      onOpenSettings: (@Sendable () -> Void)? = nil,
                      onProtectRequest: (@Sendable (String) -> Void)? = nil,
                      onRelockRequest: (@Sendable (String) -> Void)? = nil,
                      onPauseRequest: (@Sendable (Int) -> Void)? = nil,
                      onUnprotectRequest: (@Sendable (String) -> Void)? = nil,
                      onResumeRequest: (@Sendable () -> Void)? = nil) -> Bool {
        self.onBlockedHit = onBlockedHit
        self.onLockRequest = onLockRequest
        self.onActivity = onActivity
        self.onOpenSettings = onOpenSettings
        self.onProtectRequest = onProtectRequest
        self.onRelockRequest = onRelockRequest
        self.onPauseRequest = onPauseRequest
        self.onUnprotectRequest = onUnprotectRequest
        self.onResumeRequest = onResumeRequest
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        // KRYTYCZNE: nasłuch na IPv4 127.0.0.1 - PAC i przeglądarka łączą się przez
        // „127.0.0.1", a domyślny listener wchodzi na IPv6 (*:port) i odrzuca IPv4.
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: nwPort)
        guard let listener = try? NWListener(using: params) else { return false }
        listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
        listener.start(queue: queue)
        self.listener = listener
        return true
    }

    public func stop() {
        listener?.cancel(); listener = nil
    }

    // MARK: - Obsługa połączenia

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { conn.cancel(); return }
            guard let data, !data.isEmpty, error == nil,
                  let head = String(data: data, encoding: .ascii) else { conn.cancel(); return }
            let firstLine = head.components(separatedBy: "\r\n").first ?? head
            let parts = firstLine.split(separator: " ")
            guard parts.count >= 2 else { conn.cancel(); return }
            let method = parts[0].uppercased()
            let target = String(parts[1])

            // Żądanie BEZPOŚREDNIE do nas (origin-form „GET /…") - to system pobiera
            // plik PAC. Serwujemy go po HTTP (file:// PAC nie jest honorowany).
            if target.hasPrefix("/") {
                if target.hasPrefix(WebProxyServer.pacPath) {
                    self.servePAC(conn)
                } else if target.hasPrefix("/privio/extensions") {
                    self.serveExtensionStatuses(conn)
                } else if target.hasPrefix("/privio/config") {
                    self.serveExtensionConfig(conn, target: target)
                } else if target.hasPrefix("/privio/request-unlock") {
                    self.requestExtensionUnlock(conn, target: target)
                } else if target.hasPrefix("/privio/lock") {
                    self.requestExtensionLock(conn, target: target)
                } else if target.hasPrefix("/privio/activity") {
                    self.requestExtensionActivity(conn, target: target)
                } else if target.hasPrefix("/privio/open-settings") {
                    self.requestOpenSettings(conn)
                } else if target.hasPrefix("/privio/protect") {
                    self.requestProtect(conn, target: target)
                } else if target.hasPrefix("/privio/relock") {
                    self.requestRelock(conn, target: target)
                } else if target.hasPrefix("/privio/request-pause") {
                    self.requestPause(conn, target: target)
                } else if target.hasPrefix("/privio/request-unprotect") {
                    self.requestUnprotect(conn, target: target)
                } else if target.hasPrefix("/privio/resume") {
                    self.requestResume(conn)
                } else if method == "OPTIONS" {
                    self.sendHTTP(conn, status: "204 No Content", body: "", contentType: "text/plain")
                } else {
                    conn.send(content: Data("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n".utf8),
                              completion: .contentProcessed { _ in conn.cancel() })
                }
                return
            }

            if method == "CONNECT" {                       // HTTPS tunel
                let hp = target.split(separator: ":")
                let host = String(hp.first ?? "")
                let originPort = UInt16(hp.count > 1 ? hp[1] : "443") ?? 443
                if let domain = self.blockedMatch(host) {
                    PrivioLog.enforcement.info("proxy: BLOK CONNECT \(host, privacy: .public) (match \(domain, privacy: .public))")
                    self.blockConnect(conn)
                    return
                }
                PrivioLog.enforcement.debug("proxy: tunel CONNECT \(host, privacy: .public)")
                self.openTunnel(client: conn, host: host, port: originPort, replay: nil, connect: true)
            } else {                                       // zwykły HTTP
                let host = self.host(fromHTTP: head, target: target)
                if let domain = self.blockedMatch(host) {
                    PrivioLog.enforcement.info("proxy: BLOK HTTP \(host, privacy: .public) (match \(domain, privacy: .public))")
                    self.interstitial(conn, host: host)
                    return
                }
                self.openTunnel(client: conn, host: host, port: 80, replay: data, connect: false)
            }
        }
    }

    // MARK: - Chrome extension API (loopback only)

    private func serveExtensionConfig(_ conn: NWConnection, target: String) {
        if let components = URLComponents(string: "http://127.0.0.1\(target)"),
           let browser = components.queryItems?.first(where: { $0.name == "browser" })?.value,
           !browser.isEmpty {
            let version = components.queryItems?.first(where: { $0.name == "version" })?.value ?? "unknown"
            lock.lock(); _extensions[browser] = (version, Date()); lock.unlock()
        }
        let pausedEpoch = pausedUntilSnapshot().map { $0.timeIntervalSince1970 } ?? 0
        let object: [String: Any] = ["routed": routedSnapshot(), "configured": configuredSnapshot(),
                                     "blocked": blockedSnapshot(),
                                     "protectionEnabled": protectionEnabledSnapshot(),
                                     "pausedUntil": pausedEpoch,
                                     "language": languageSnapshot(),
                                     "appVersion": appVersionSnapshot()]
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        sendHTTP(conn, status: "200 OK", data: data, contentType: "application/json")
    }

    private func serveExtensionStatuses(_ conn: NWConnection) {
        lock.lock()
        let now = Date()
        let extensions = _extensions.map { browser, value in
            ["browser": browser, "version": value.version,
             "active": now.timeIntervalSince(value.lastSeen) < 10,
             "lastSeen": value.lastSeen.timeIntervalSince1970] as [String: Any]
        }.sorted { ($0["browser"] as? String ?? "") < ($1["browser"] as? String ?? "") }
        lock.unlock()
        let data = (try? JSONSerialization.data(withJSONObject: ["extensions": extensions]))
            ?? Data(#"{"extensions":[]}"#.utf8)
        sendHTTP(conn, status: "200 OK", data: data, contentType: "application/json")
    }

    private func requestExtensionUnlock(_ conn: NWConnection, target: String) {
        guard let components = URLComponents(string: "http://127.0.0.1\(target)"),
              let requested = components.queryItems?.first(where: { $0.name == "domain" })?.value,
              let domain = blockedMatch(requested) else {
            sendHTTP(conn, status: "200 OK", body: #"{"state":"unlocked"}"#,
                     contentType: "application/json")
            return
        }
        PrivioLog.enforcement.info("extension: żądanie odblokowania \(domain, privacy: .public)")
        onBlockedHit?(domain)
        sendHTTP(conn, status: "202 Accepted", body: #"{"state":"authenticating"}"#,
                 contentType: "application/json")
    }

    private func requestExtensionLock(_ conn: NWConnection, target: String) {
        guard let components = URLComponents(string: "http://127.0.0.1\(target)"),
              let domain = components.queryItems?.first(where: { $0.name == "domain" })?.value,
              routedSnapshot().contains(where: { domain == $0 || domain.hasSuffix("." + $0) }) else {
            sendHTTP(conn, status: "400 Bad Request", body: #"{"state":"invalid"}"#,
                     contentType: "application/json")
            return
        }
        PrivioLog.enforcement.info("extension: ostatnia karta zamknięta dla \(domain, privacy: .public)")
        onLockRequest?(domain)
        sendHTTP(conn, status: "200 OK", body: #"{"state":"locked"}"#,
                 contentType: "application/json")
    }

    private func requestExtensionActivity(_ conn: NWConnection, target: String) {
        guard let components = URLComponents(string: "http://127.0.0.1\(target)"),
              let requested = components.queryItems?.first(where: { $0.name == "domain" })?.value,
              let domain = routedSnapshot().first(where: {
                  requested == $0 || requested.hasSuffix("." + $0)
              }) else {
            sendHTTP(conn, status: "400 Bad Request", body: #"{"state":"invalid"}"#,
                     contentType: "application/json")
            return
        }
        let isActive = components.queryItems?.first(where: { $0.name == "active" })?.value != "0"
        onActivity?(domain, isActive)
        sendHTTP(conn, status: "200 OK", body: #"{"state":"recorded"}"#,
                 contentType: "application/json")
    }

    /// Rozszerzenie prosi o otwarcie panelu Privio (przycisk „Otwórz ustawienia").
    /// To NIE odblokowuje niczego - aplikacja podnosi okno, które i tak jest za
    /// bramką Touch ID (SensitiveAction.openPrivio), więc nie osłabia ochrony.
    private func requestOpenSettings(_ conn: NWConnection) {
        PrivioLog.enforcement.info("extension: żądanie otwarcia ustawień Privio")
        onOpenSettings?()
        sendHTTP(conn, status: "200 OK", body: #"{"state":"opening"}"#,
                 contentType: "application/json")
    }

    /// „Chroń tę stronę" - dodaje bieżącą domenę do ochrony. WZMACNIA ochronę,
    /// więc nie wymaga Touch ID (aplikacja tworzy cel z ustawieniami domyślnymi).
    private func requestProtect(_ conn: NWConnection, target: String) {
        guard let components = URLComponents(string: "http://127.0.0.1\(target)"),
              let domain = components.queryItems?.first(where: { $0.name == "domain" })?.value,
              !domain.isEmpty else {
            sendHTTP(conn, status: "400 Bad Request", body: #"{"state":"invalid"}"#,
                     contentType: "application/json")
            return
        }
        PrivioLog.enforcement.info("extension: żądanie ochrony \(domain, privacy: .public)")
        onProtectRequest?(domain)
        sendHTTP(conn, status: "200 OK", body: #"{"state":"protected"}"#,
                 contentType: "application/json")
    }

    /// „Zablokuj teraz" - ręczna, natychmiastowa blokada chronionej (odblokowanej)
    /// domeny. WZMACNIA ochronę → bez Touch ID. Waliduje, że domena jest kierowana.
    private func requestRelock(_ conn: NWConnection, target: String) {
        guard let components = URLComponents(string: "http://127.0.0.1\(target)"),
              let requested = components.queryItems?.first(where: { $0.name == "domain" })?.value,
              let domain = routedSnapshot().first(where: {
                  requested == $0 || requested.hasSuffix("." + $0)
              }) else {
            sendHTTP(conn, status: "400 Bad Request", body: #"{"state":"invalid"}"#,
                     contentType: "application/json")
            return
        }
        PrivioLog.enforcement.info("extension: ręczna blokada \(domain, privacy: .public)")
        onRelockRequest?(domain)
        sendHTTP(conn, status: "200 OK", body: #"{"state":"locked"}"#,
                 contentType: "application/json")
    }

    /// „Wstrzymaj ochronę na N min" - OSŁABIA ochronę, więc tylko sygnalizuje;
    /// aplikacja bramkuje to Touch ID. Minuty ograniczamy do rozsądnego zakresu.
    private func requestPause(_ conn: NWConnection, target: String) {
        let raw = URLComponents(string: "http://127.0.0.1\(target)")?
            .queryItems?.first(where: { $0.name == "minutes" })?.value
        guard let minutes = raw.flatMap({ Int($0) }), (0...1440).contains(minutes) else {
            sendHTTP(conn, status: "400 Bad Request", body: #"{"state":"invalid"}"#,
                     contentType: "application/json")
            return
        }
        if minutes == 0 {
            PrivioLog.enforcement.info("extension: żądanie wyłączenia do ręcznego wznowienia")
        } else {
            PrivioLog.enforcement.info("extension: żądanie wstrzymania na \(minutes, privacy: .public) min")
        }
        onPauseRequest?(minutes)
        sendHTTP(conn, status: "202 Accepted", body: #"{"state":"authenticating"}"#,
                 contentType: "application/json")
    }

    /// Usunięcie domeny osłabia ochronę, więc endpoint jedynie publikuje żądanie.
    /// Faktyczne usunięcie następuje w aplikacji dopiero po Touch ID/haśle.
    private func requestUnprotect(_ conn: NWConnection, target: String) {
        guard let components = URLComponents(string: "http://127.0.0.1\(target)"),
              let requested = components.queryItems?.first(where: { $0.name == "domain" })?.value,
              let domain = configuredSnapshot().first(where: {
                  requested == $0 || requested.hasSuffix("." + $0)
              }) else {
            sendHTTP(conn, status: "400 Bad Request", body: #"{"state":"invalid"}"#,
                     contentType: "application/json")
            return
        }
        PrivioLog.enforcement.info("extension: żądanie usunięcia ochrony \(domain, privacy: .public)")
        onUnprotectRequest?(domain)
        sendHTTP(conn, status: "202 Accepted", body: #"{"state":"authenticating"}"#,
                 contentType: "application/json")
    }

    /// „Wznów" - WZMACNIA ochronę, więc bez Touch ID.
    private func requestResume(_ conn: NWConnection) {
        PrivioLog.enforcement.info("extension: żądanie wznowienia ochrony")
        onResumeRequest?()
        sendHTTP(conn, status: "200 OK", body: #"{"state":"resumed"}"#,
                 contentType: "application/json")
    }

    private func sendHTTP(_ conn: NWConnection, status: String, body: String, contentType: String) {
        sendHTTP(conn, status: status, data: Data(body.utf8), contentType: contentType)
    }

    private func sendHTTP(_ conn: NWConnection, status: String, data: Data, contentType: String) {
        var head = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\n"
        head += "Content-Length: \(data.count)\r\nCache-Control: no-store\r\n"
        head += "Access-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, OPTIONS\r\n"
        head += "Connection: close\r\n\r\n"
        var response = Data(head.utf8); response.append(data)
        conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
    }

    /// Otwiera połączenie do origin i zaczyna dwukierunkowy relay. Dla CONNECT
    /// wysyła klientowi „200 Connection Established"; dla HTTP odtwarza pierwsze
    /// żądanie do origin.
    private func openTunnel(client: NWConnection, host: String, port: UInt16, replay: Data?, connect: Bool) {
        guard !host.isEmpty, let nwPort = NWEndpoint.Port(rawValue: port) else { client.cancel(); return }
        // To połączenie jest "drugą nogą" lokalnego proxy. Łączymy się z
        // rozwiązanym adresem IP, a nie ponownie z nazwą domeny: systemowy PAC
        // dopasowuje chronione domeny, więc użycie nazwy skierowałoby tę nogę z
        // powrotem na 127.0.0.1 i utworzyło nieskończoną pętlę proxy.
        guard let directHost = resolveDirectHost(host) else {
            PrivioLog.enforcement.error("proxy: DNS failed for \(host, privacy: .public)")
            client.cancel()
            return
        }
        let origin = NWConnection(host: directHost, port: nwPort, using: .tcp)
        origin.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                if connect {
                    client.send(content: Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8),
                                completion: .contentProcessed { _ in
                                    self.relay(client, origin); self.relay(origin, client)
                                })
                } else {
                    origin.send(content: replay ?? Data(), completion: .contentProcessed { _ in
                        self.relay(client, origin); self.relay(origin, client)
                    })
                }
            case .failed(let error):
                PrivioLog.enforcement.error("proxy: origin \(host, privacy: .public):\(port) failed: \(String(describing: error), privacy: .public)")
                client.cancel()
                origin.cancel()
            case .cancelled:
                client.cancel()
            default: break
            }
        }
        origin.start(queue: queue)
    }

    /// Zwraca numeryczny adres hosta. Połączenia do IP nie pasują do domen w PAC,
    /// więc omijają lokalne proxy także wtedy, gdy systemowe auto-proxy jest aktywne.
    private func resolveDirectHost(_ host: String) -> NWEndpoint.Host? {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return nil }
        defer { freeaddrinfo(result) }

        var address = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(first.pointee.ai_addr, first.pointee.ai_addrlen,
                          &address, socklen_t(address.count), nil, 0,
                          NI_NUMERICHOST) == 0 else { return nil }
        return NWEndpoint.Host(String(cString: address))
    }

    private func relay(_ from: NWConnection, _ to: NWConnection) {
        from.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                to.send(content: data, completion: .contentProcessed { sendError in
                    if isComplete || error != nil || sendError != nil {
                        to.cancel(); from.cancel()
                    } else {
                        self?.relay(from, to)
                    }
                })
            } else if isComplete || error != nil {
                to.cancel(); from.cancel()
            } else {
                self?.relay(from, to)
            }
        }
    }

    // MARK: - Odpowiedzi blokady

    /// Serwuje plik PAC (system pobiera go po HTTP z tego serwera).
    private func servePAC(_ conn: NWConnection) {
        let pac = SystemWebProxy.pacContents(port: port, domains: routedSnapshot())
        let resp = "HTTP/1.1 200 OK\r\n"
            + "Content-Type: application/x-ns-proxy-autoconfig\r\n"
            + "Content-Length: \(pac.utf8.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
            + pac
        conn.send(content: Data(resp.utf8), completion: .contentProcessed { _ in conn.cancel() })
    }

    /// Blokada tunelu HTTPS: 403. PAC nie ma już fallbacku DIRECT dla chronionych
    /// domen, więc przeglądarka nie obchodzi blokady - pokazuje błąd tunelu.
    private func blockConnect(_ conn: NWConnection) {
        conn.send(content: Data("HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n".utf8),
                  completion: .contentProcessed { _ in conn.cancel() })
    }

    private func interstitial(_ conn: NWConnection, host: String) {
        let body = """
        <!doctype html><meta charset="utf-8"><title>Blocked by Privio</title>
        <style>body{font:16px -apple-system,Helvetica,Arial;color:#1b1d29;background:#f4f5fb;\
        display:flex;min-height:90vh;align-items:center;justify-content:center;text-align:center}\
        .c{max-width:420px}b{color:#12131c}</style>
        <div class=c><h2>🔒 Zablokowane przez Privio</h2>
        <p><b>\(host)</b> jest chronione. Odblokuj je w aplikacji Privio (Touch ID),\
        a potem odśwież tę stronę.</p></div>
        """
        let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body
        conn.send(content: Data(resp.utf8), completion: .contentProcessed { _ in conn.cancel() })
    }

    // MARK: - Parsowanie hosta

    private func host(fromHTTP head: String, target: String) -> String {
        // origin-form: „GET http://host/path" → wyłuskaj host
        if let range = target.range(of: "://") {
            let rest = target[range.upperBound...]
            let hostPart = rest.split(separator: "/").first.map(String.init) ?? String(rest)
            return hostPart.split(separator: ":").first.map(String.init) ?? hostPart
        }
        // nagłówek Host:
        for line in head.components(separatedBy: "\r\n") where line.lowercased().hasPrefix("host:") {
            let value = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            return value.split(separator: ":").first.map(String.init) ?? value
        }
        return ""
    }
}
