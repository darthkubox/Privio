import Foundation

/// Diagnostyka modułu „Blokada po odejściu".
///
/// Domyślnie **wyłączona**; włączana opt-in flagą `UserDefaults` `privio.proximity.diag`
/// (`defaults write com.privio.Privio privio.proximity.diag -bool YES`, potem restart
/// aplikacji). Działa również w buildzie **release**, żeby dało się zdiagnozować
/// fałszywe blokady na realnym sprzęcie - czego dawna bramka `#if DEBUG` nie pozwalała.
///
/// Zapisuje do `~/Library/Logs/Privio/proximity.log` (a nie do świato-czytelnego
/// `/tmp`) z prostą rotacją: po przekroczeniu `maxBytes` bieżący plik ląduje jako
/// `proximity.1.log`, a log startuje od nowa.
enum ProximityDiag {
    /// Klucz `UserDefaults` włączający logowanie.
    static let defaultsKey = "privio.proximity.diag"
    private static let maxBytes: UInt64 = 512 * 1024

    private static let queue = DispatchQueue(label: "com.privio.diag")
    private static let iso = ISO8601DateFormatter()
    /// Odczytane raz przy pierwszym użyciu - zmiana flagi wymaga restartu aplikacji.
    private static let enabled = UserDefaults.standard.bool(forKey: defaultsKey)

    private static let fileURL: URL? = {
        guard let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent("Logs/Privio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("proximity.log")
    }()

    /// `@autoclosure`: gdy diagnostyka jest wyłączona, komunikat nie jest nawet budowany.
    static func log(_ message: @autoclosure () -> String) {
        guard enabled, let url = fileURL else { return }
        let line = "\(iso.string(from: Date()))  \(message())\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            rotateIfNeeded(url)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile(); handle.write(data); try? handle.close()
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private static func rotateIfNeeded(_ url: URL) {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? nil
        guard let size, size > maxBytes else { return }
        let rotated = url.deletingPathExtension().appendingPathExtension("1.log")
        try? FileManager.default.removeItem(at: rotated)
        try? FileManager.default.moveItem(at: url, to: rotated)
    }
}
