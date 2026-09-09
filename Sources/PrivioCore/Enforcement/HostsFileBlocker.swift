import Foundation

public enum WebsiteBlockingError: Error, Sendable, Equatable {
    /// Użytkownik anulował okno autoryzacji administratora.
    case authorizationCancelled
    /// Zapis do /etc/hosts nie powiódł się (komunikat diagnostyczny).
    case writeFailed(String)
}

/// Produkcyjna implementacja blokady stron: zarządza sekcją Privio w `/etc/hosts`
/// i odświeża cache DNS. Zapis wymaga uprawnień roota, więc idzie przez jednorazową
/// autoryzację administratora (`do shell script … with administrator privileges` -
/// na Apple Silicon okno oferuje Touch ID). Docelowo zastąpi to uprzywilejowany
/// helper przez XPC (bez ciągłych promptów), gdy będzie Developer ID.
///
/// Cała LOGIKA składania treści jest w `PrivioHostsBlock` (czysta, testowalna);
/// tutaj tylko I/O i eskalacja uprawnień.
public struct HostsFileBlocker: WebsiteBlocking {
    private let hostsPath: String

    public init(hostsPath: String = "/etc/hosts") {
        self.hostsPath = hostsPath
    }

    public func setBlockedHosts(_ hostnames: [String]) async throws {
        let current = (try? String(contentsOfFile: hostsPath, encoding: .utf8)) ?? ""
        let updated = PrivioHostsBlock.apply(hostnames: hostnames, to: current)
        guard updated != current else { return }   // nic się nie zmienia → bez promptu
        try writePrivileged(updated)
    }

    public func clearAll() async throws {
        try await setBlockedHosts([])
    }

    // MARK: - Uprzywilejowany zapis

    private func writePrivileged(_ contents: String) throws {
        // Nową treść zapisujemy najpierw do pliku tymczasowego (jako użytkownik),
        // a uprzywilejowane polecenie tylko kopiuje ją na miejsce i odświeża DNS.
        // Dzięki temu w skrypcie nie ma treści pliku (brak problemów z eskejpowaniem).
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("privio-hosts-\(UUID().uuidString)")
        do {
            try contents.write(to: tmp, atomically: true, encoding: .utf8)
        } catch {
            throw WebsiteBlockingError.writeFailed("temp write: \(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(at: tmp) }

        let shell = "cat \(shellQuote(tmp.path)) > \(shellQuote(hostsPath)) && "
            + "chmod 644 \(shellQuote(hostsPath)); "
            + "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder"
        let script = "do shell script \"\(appleScriptEscape(shell))\" with administrator privileges"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        let err = Pipe()
        proc.standardError = err
        proc.standardOutput = Pipe()
        do {
            try proc.run()
        } catch {
            throw WebsiteBlockingError.writeFailed("osascript launch: \(error.localizedDescription)")
        }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            // -128 = użytkownik anulował autoryzację.
            if msg.contains("-128") || msg.localizedCaseInsensitiveContains("cancel") {
                throw WebsiteBlockingError.authorizationCancelled
            }
            throw WebsiteBlockingError.writeFailed(msg.isEmpty ? "exit \(proc.terminationStatus)" : msg)
        }
    }

    // MARK: - Eskejpowanie

    /// Cudzysłów pojedynczy dla powłoki (bezpieczny wobec dowolnej ścieżki).
    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Eskejpowanie do literału stringa AppleScript (`\` i `"`).
    private func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
