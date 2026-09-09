import Foundation

/// Uruchamia polecenie powłoki z uprawnieniami administratora (jedno okno
/// autoryzacji; na Apple Silicon może oferować Touch ID). Skrypt zapisujemy do
/// pliku tymczasowego i wołamy przez `osascript`, żeby uniknąć problemów z
/// eskejpowaniem długich poleceń w literałach AppleScript.
enum PrivilegedShell {
    /// Wykonuje `script` (treść dla `/bin/sh`) jako administrator. Rzuca
    /// `WebsiteBlockingError.authorizationCancelled`, gdy użytkownik anuluje.
    static func run(_ script: String) throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("privio-priv-\(UUID().uuidString).sh")
        do {
            try script.write(to: tmp, atomically: true, encoding: .utf8)
        } catch {
            throw WebsiteBlockingError.writeFailed("temp script: \(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(at: tmp) }

        let osa = "do shell script \"/bin/sh \(appleScriptEscape(shellQuote(tmp.path)))\" with administrator privileges"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", osa]
        let err = Pipe()
        proc.standardError = err
        proc.standardOutput = Pipe()
        do { try proc.run() } catch {
            throw WebsiteBlockingError.writeFailed("osascript launch: \(error.localizedDescription)")
        }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if msg.contains("-128") || msg.localizedCaseInsensitiveContains("cancel") {
                throw WebsiteBlockingError.authorizationCancelled
            }
            throw WebsiteBlockingError.writeFailed(msg.isEmpty ? "exit \(proc.terminationStatus)" : msg)
        }
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    private static func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
