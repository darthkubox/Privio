import XCTest
import Network
@testable import PrivioCore

final class WebsiteBlockingTests: XCTestCase {

    // MARK: - Normalizacja / dopasowanie

    func testNormalizeStripsSchemeWWWPathPort() {
        XCTAssertEqual(WebTarget.normalize("https://www.Example.com/panel?x=1"), "example.com")
        XCTAssertEqual(WebTarget.normalize("  HTTP://Example.COM:8080  "), "example.com")
        XCTAssertEqual(WebTarget.normalize("www.sub.example.com"), "sub.example.com")
        XCTAssertEqual(WebTarget.normalize("example.com"), "example.com")
        XCTAssertEqual(WebTarget.normalize("user:pass@example.com/x"), "example.com")
    }

    func testMatchesDomainAndSubdomains() {
        let t = WebTarget(domain: "example.com")
        XCTAssertTrue(t.matches(host: "example.com"))
        XCTAssertTrue(t.matches(host: "www.example.com"))
        XCTAssertTrue(t.matches(host: "mail.example.com"))
        XCTAssertFalse(t.matches(host: "notexample.com"))
        XCTAssertFalse(t.matches(host: "example.com.evil.com"))
    }

    func testBlockedHostnamesIncludesWWW() {
        XCTAssertEqual(WebTarget(domain: "example.com", includeWWW: true).blockedHostnames,
                       ["example.com", "www.example.com"])
        XCTAssertEqual(WebTarget(domain: "example.com", includeWWW: false).blockedHostnames,
                       ["example.com"])
    }

    // MARK: - Sekcja /etc/hosts

    func testSectionMapsToBlackholeSortedNoDuplicates() {
        let s = PrivioHostsBlock.section(for: ["b.com", "a.com", "a.com"])
        XCTAssertTrue(s.hasPrefix(PrivioHostsBlock.begin))
        XCTAssertTrue(s.hasSuffix(PrivioHostsBlock.end))
        XCTAssertTrue(s.contains("0.0.0.0\ta.com"))
        XCTAssertTrue(s.contains("::1\tb.com"))
        // posortowane: a.com przed b.com
        XCTAssertLessThan(s.range(of: "a.com")!.lowerBound, s.range(of: "b.com")!.lowerBound)
        // brak duplikatu a.com w linii 0.0.0.0
        XCTAssertEqual(s.components(separatedBy: "0.0.0.0\ta.com").count - 1, 1)
    }

    func testSectionEmptyForNoHosts() {
        XCTAssertEqual(PrivioHostsBlock.section(for: []), "")
    }

    func testApplyIsIdempotent() {
        let base = "127.0.0.1\tlocalhost\n255.255.255.255\tbroadcasthost\n"
        let once = PrivioHostsBlock.apply(hostnames: ["example.com"], to: base)
        let twice = PrivioHostsBlock.apply(hostnames: ["example.com"], to: once)
        XCTAssertEqual(once, twice, "apply musi być idempotentne (nie dokładać kolejnych sekcji)")
        XCTAssertTrue(once.contains("127.0.0.1\tlocalhost"), "oryginalna treść zachowana")
        XCTAssertEqual(once.components(separatedBy: PrivioHostsBlock.begin).count - 1, 1)
    }

    func testApplyThenRemoveRestoresOriginal() {
        let base = "127.0.0.1\tlocalhost\n255.255.255.255\tbroadcasthost\n"
        let blocked = PrivioHostsBlock.apply(hostnames: ["example.com", "www.example.com"], to: base)
        XCTAssertNotEqual(blocked, base)
        let restored = PrivioHostsBlock.removed(from: blocked)
        XCTAssertEqual(restored, base, "po usunięciu sekcji Privio treść wraca do oryginału")
    }

    func testApplyEmptyRemovesSection() {
        let base = "127.0.0.1\tlocalhost\n"
        let blocked = PrivioHostsBlock.apply(hostnames: ["x.com"], to: base)
        let cleared = PrivioHostsBlock.apply(hostnames: [], to: blocked)
        XCTAssertFalse(cleared.contains(PrivioHostsBlock.begin))
        XCTAssertEqual(cleared, base)
    }

    // MARK: - Wsteczna zgodność persistencji

    func testPersistedStateDecodesWithoutWebTargets() throws {
        let json = #"{"apps":[],"configuration":\#(configJSON())}"#
        let state = try JSONDecoder().decode(PersistedState.self, from: Data(json.utf8))
        XCTAssertTrue(state.webTargets.isEmpty, "brak pola webTargets → pusta lista, bez błędu")
    }

    func testPersistedStateRoundTripsWebTargets() throws {
        var state = PersistedState()
        state.webTargets = [WebTarget(domain: "example.com"), WebTarget(domain: "news.ycombinator.com")]
        let data = try JSONEncoder().encode(state)
        let back = try JSONDecoder().decode(PersistedState.self, from: data)
        XCTAssertEqual(back.webTargets.map(\.domain), ["example.com", "news.ycombinator.com"])
    }

    private func configJSON() -> String {
        String(data: try! JSONEncoder().encode(AppConfiguration.default), encoding: .utf8)!
    }

    // MARK: - Enforcement (proxy, bez sieci/admina)

    private func serviceWithProxy() -> (InProcessEnforcementService, WebProxyServer) {
        let proxy = WebProxyServer(port: 0)   // nie startujemy nasłuchu - tylko zestaw domen
        let config = AppConfiguration(websiteBlockingEnabled: true)
        let service = InProcessEnforcementService(
            webProxy: proxy, initialState: EnforcementState(configuration: config))
        return (service, proxy)
    }

    func testLockedWebTargetUpdatesProxyAndDisablingClearsIt() async {
        let (service, proxy) = serviceWithProxy()
        await service.addWebTarget(WebTarget(domain: "Example.com"))
        XCTAssertEqual(proxy.currentBlockedDomains(), ["example.com"],
                       "zablokowany cel → domena w zestawie proxy")

        let id = await service.currentState().webTargets.first!.id
        await service.setProtectionEnabled(false, forWebID: id)
        XCTAssertEqual(proxy.currentBlockedDomains(), [], "wyłączenie ochrony celu → brak bloku")
    }

    func testModuleDisabledMeansNoProxyBlocks() async {
        let proxy = WebProxyServer(port: 0)
        // moduł stron WYŁĄCZONY → mimo zablokowanego celu proxy nic nie blokuje
        let service = InProcessEnforcementService(
            webProxy: proxy,
            initialState: EnforcementState(configuration: AppConfiguration(websiteBlockingEnabled: false)))
        await service.addWebTarget(WebTarget(domain: "example.com"))
        XCTAssertEqual(proxy.currentBlockedDomains(), [])
    }

    func testStartupNeverChangesPersistedWebsiteProtectionSetting() async {
        let enabled = AppConfiguration(websiteBlockingEnabled: true)
        let service = InProcessEnforcementService(
            webProxy: nil,
            initialState: EnforcementState(configuration: enabled))

        // Subskrypcja uruchamia pełną ścieżkę startową używaną po aktualizacji.
        let updates = await service.stateUpdates()
        var iterator = updates.makeAsyncIterator()
        _ = await iterator.next()

        let state = await service.currentState()
        XCTAssertTrue(state.configuration.websiteBlockingEnabled,
                      "start/aktualizacja nie może wyłączać ustawienia użytkownika")
    }

    /// Regresja: proxy MUSI słuchać na IPv4 127.0.0.1 (PAC/przeglądarka tam się łączą).
    /// Wcześniej wchodziło na IPv6 (*:port) i odrzucało IPv4 → „nie blokuje w ogóle".
    func testProxyListensOnIPv4Loopback() {
        let proxy = WebProxyServer(port: 8991)
        XCTAssertTrue(proxy.start { _ in }, "serwer proxy powinien wystartować")
        defer { proxy.stop() }

        let exp = expectation(description: "IPv4 połączenie do proxy")
        let conn = NWConnection(host: .ipv4(.loopback), port: 8991, using: .tcp)
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready: exp.fulfill(); conn.cancel()
            case .failed, .cancelled: conn.cancel()
            default: break
            }
        }
        conn.start(queue: .global())
        wait(for: [exp], timeout: 3)
    }

    /// Kluczowe: proxy serwuje PAC po HTTP (file:// nie jest honorowany przez macOS).
    func testProxyServesPACOverHTTP() {
        let proxy = WebProxyServer(port: 8992)
        XCTAssertTrue(proxy.start { _ in })
        defer { proxy.stop() }
        proxy.updateRoutedDomains(["onet.pl"])

        let exp = expectation(description: "PAC po HTTP")
        var body = ""
        let conn = NWConnection(host: .ipv4(.loopback), port: 8992, using: .tcp)
        conn.stateUpdateHandler = { state in
            if case .ready = state {
                conn.send(content: Data("GET /privio.pac HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8),
                          completion: .idempotent)
                conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                    if let data { body = String(data: data, encoding: .utf8) ?? "" }
                    exp.fulfill(); conn.cancel()
                }
            }
        }
        conn.start(queue: .global())
        wait(for: [exp], timeout: 3)
        XCTAssertTrue(body.contains("onet.pl"), "PAC zawiera chronioną domenę")
        XCTAssertTrue(body.contains("PROXY 127.0.0.1:8992"), "kieruje przez proxy")
        XCTAssertFalse(body.contains("; DIRECT"), "chroniona domena NIE ma fallbacku ; DIRECT (obchodziłby blokadę)")
    }

    /// Test end-to-end bez internetu: CONNECT przez proxy musi zestawić tunel do
    /// lokalnego origin i przenieść dane w obie strony.
    func testProxyRelaysConnectTunnelToLocalOrigin() throws {
        let originPort: NWEndpoint.Port = 8993
        let origin = try NWListener(using: .tcp, on: originPort)
        let originReady = expectation(description: "lokalny origin słucha")
        origin.stateUpdateHandler = { state in
            if case .ready = state { originReady.fulfill() }
        }
        origin.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, _ in
                guard String(data: data ?? Data(), encoding: .utf8) == "ping" else {
                    connection.cancel(); return
                }
                connection.send(content: Data("pong".utf8),
                                completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        origin.start(queue: .global())
        defer { origin.cancel() }
        wait(for: [originReady], timeout: 3)

        let proxy = WebProxyServer(port: 8994)
        XCTAssertTrue(proxy.start { _ in })
        defer { proxy.stop() }

        let tunnelReady = expectation(description: "proxy zwraca 200")
        let relayed = expectation(description: "odpowiedź origin wraca tunelem")
        let client = NWConnection(host: .ipv4(.loopback), port: 8994, using: .tcp)
        client.stateUpdateHandler = { state in
            guard case .ready = state else { return }
            let request = "CONNECT 127.0.0.1:\(originPort.rawValue) HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
            client.send(content: Data(request.utf8), completion: .contentProcessed { error in
                XCTAssertNil(error)
                client.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, error in
                    XCTAssertNil(error)
                    XCTAssertTrue(String(data: data ?? Data(), encoding: .utf8)?.contains("200 Connection Established") == true)
                    tunnelReady.fulfill()
                    client.send(content: Data("ping".utf8), completion: .contentProcessed { error in
                        XCTAssertNil(error)
                        client.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, error in
                            XCTAssertNil(error)
                            XCTAssertEqual(String(data: data ?? Data(), encoding: .utf8), "pong")
                            relayed.fulfill()
                            client.cancel()
                        }
                    })
                }
            })
        }
        client.start(queue: .global())
        wait(for: [tunnelReady, relayed], timeout: 5)
    }

    func testExtensionUnlockEndpointIsTheOnlySourceOfAuthPrompt() {
        let proxy = WebProxyServer(port: 8996)
        proxy.updateRoutedDomains(["example.com"])
        proxy.updateBlockedDomains(["example.com"])
        let hit = expectation(description: "extension jawnie żąda Touch ID")
        XCTAssertTrue(proxy.start { domain in
            XCTAssertEqual(domain, "example.com")
            hit.fulfill()
        })
        defer { proxy.stop() }

        let response = expectation(description: "lokalne API odpowiada")
        let client = NWConnection(host: .ipv4(.loopback), port: 8996, using: .tcp)
        client.stateUpdateHandler = { state in
            guard case .ready = state else { return }
            let request = "GET /privio/request-unlock?domain=example.com HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
            client.send(content: Data(request.utf8), completion: .contentProcessed { _ in
                client.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                    XCTAssertTrue(String(data: data ?? Data(), encoding: .utf8)?.contains("202 Accepted") == true)
                    response.fulfill(); client.cancel()
                }
            })
        }
        client.start(queue: .global())
        wait(for: [hit, response], timeout: 3)
    }

    func testExtensionCanRelockDomainAfterLastTabCloses() {
        let proxy = WebProxyServer(port: 8997)
        proxy.updateRoutedDomains(["example.com"])
        let lockRequested = expectation(description: "extension żąda ponownej blokady")
        XCTAssertTrue(proxy.start(onBlockedHit: { _ in
            XCTFail("endpoint blokady nie może żądać uwierzytelnienia")
        }, onLockRequest: { domain in
            XCTAssertEqual(domain, "example.com")
            lockRequested.fulfill()
        }))
        defer { proxy.stop() }

        let response = expectation(description: "API blokady odpowiada")
        let client = NWConnection(host: .ipv4(.loopback), port: 8997, using: .tcp)
        client.stateUpdateHandler = { state in
            guard case .ready = state else { return }
            let request = "GET /privio/lock?domain=example.com HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
            client.send(content: Data(request.utf8), completion: .contentProcessed { _ in
                client.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                    XCTAssertTrue(String(data: data ?? Data(), encoding: .utf8)?.contains("200 OK") == true)
                    response.fulfill(); client.cancel()
                }
            })
        }
        client.start(queue: .global())
        wait(for: [lockRequested, response], timeout: 3)
    }

    func testExtensionReportsFocusedWebsiteActivity() {
        let proxy = WebProxyServer(port: 8998)
        proxy.updateRoutedDomains(["example.com"])
        let activityReported = expectation(description: "extension zgłasza aktywność karty")
        XCTAssertTrue(proxy.start(onBlockedHit: { _ in
            XCTFail("aktywność nie może żądać uwierzytelnienia")
        }, onActivity: { domain, isActive in
            XCTAssertEqual(domain, "example.com")
            XCTAssertTrue(isActive)
            activityReported.fulfill()
        }))
        defer { proxy.stop() }

        let response = expectation(description: "API aktywności odpowiada")
        let client = NWConnection(host: .ipv4(.loopback), port: 8998, using: .tcp)
        client.stateUpdateHandler = { state in
            guard case .ready = state else { return }
            let request = "GET /privio/activity?domain=example.com&active=1 HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
            client.send(content: Data(request.utf8), completion: .contentProcessed { _ in
                client.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                    XCTAssertTrue(String(data: data ?? Data(), encoding: .utf8)?.contains("200 OK") == true)
                    response.fulfill(); client.cancel()
                }
            })
        }
        client.start(queue: .global())
        wait(for: [activityReported, response], timeout: 3)
    }

    func testExtensionHeartbeatAppearsInStatusEndpoint() {
        let proxy = WebProxyServer(port: 8999)
        XCTAssertTrue(proxy.start(onBlockedHit: { _ in }))
        defer { proxy.stop() }

        func request(_ path: String, completion: @escaping (String) -> Void) {
            let client = NWConnection(host: .ipv4(.loopback), port: 8999, using: .tcp)
            client.stateUpdateHandler = { state in
                guard case .ready = state else { return }
                let value = "GET \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
                client.send(content: Data(value.utf8), completion: .contentProcessed { _ in
                    client.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                        completion(String(data: data ?? Data(), encoding: .utf8) ?? "")
                        client.cancel()
                    }
                })
            }
            client.start(queue: .global())
        }

        let registered = expectation(description: "heartbeat registered")
        request("/privio/config?browser=Chrome&version=0.1.3") { _ in registered.fulfill() }
        wait(for: [registered], timeout: 3)

        let status = expectation(description: "status returned")
        request("/privio/extensions") { response in
            XCTAssertTrue(response.contains("Chrome"))
            XCTAssertTrue(response.contains("0.1.3"))
            XCTAssertTrue(response.contains("\"active\":true"))
            status.fulfill()
        }
        wait(for: [status], timeout: 3)
    }

    func testDuplicateDomainIsNotAddedTwice() async {
        let (service, _) = serviceWithProxy()
        await service.addWebTarget(WebTarget(domain: "example.com"))
        await service.addWebTarget(WebTarget(domain: "www.example.com"))  // ta sama domena po normalizacji
        let count = await service.currentState().webTargets.count
        XCTAssertEqual(count, 1)
    }

    func testIndefiniteWebsitePauseRequiresManualResume() async {
        let (service, _) = serviceWithProxy()
        await service.pauseWebsiteProtection(minutes: 0)
        var state = await service.currentState()
        XCTAssertTrue(state.isWebProtectionPaused)
        XCTAssertEqual(state.webPauseUntil, .distantFuture)

        await service.resumeWebsiteProtection()
        state = await service.currentState()
        XCTAssertFalse(state.isWebProtectionPaused)
        XCTAssertNil(state.webPauseUntil)
    }

    func testExtensionUnprotectOnlyPublishesAuthenticatedRequest() {
        let proxy = WebProxyServer(port: 9000)
        proxy.updateConfiguredDomains(["example.com"])
        let requested = expectation(description: "extension publikuje żądanie usunięcia")
        XCTAssertTrue(proxy.start(onBlockedHit: { _ in
            XCTFail("usunięcie ochrony nie może używać ścieżki odblokowania")
        }, onUnprotectRequest: { domain in
            XCTAssertEqual(domain, "example.com")
            requested.fulfill()
        }))
        defer { proxy.stop() }

        let response = expectation(description: "API oczekuje na autoryzację")
        let client = NWConnection(host: .ipv4(.loopback), port: 9000, using: .tcp)
        client.stateUpdateHandler = { state in
            guard case .ready = state else { return }
            let request = "GET /privio/request-unprotect?domain=www.example.com HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
            client.send(content: Data(request.utf8), completion: .contentProcessed { _ in
                client.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                    XCTAssertTrue(String(data: data ?? Data(), encoding: .utf8)?.contains("202 Accepted") == true)
                    response.fulfill()
                    client.cancel()
                }
            })
        }
        client.start(queue: .global())
        wait(for: [requested, response], timeout: 3)
    }
}
