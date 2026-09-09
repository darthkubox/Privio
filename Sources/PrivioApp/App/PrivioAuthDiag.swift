import AppKit

/// TYMCZASOWA diagnostyka fokusu promptu Touch ID. Zapisuje do /tmp/privio_auth.log,
/// kto trzyma okno kluczowe / front w trakcie autoryzacji - żeby ustalić, co odbiera
/// fokus systemowemu promptowi. USUNĄĆ po rozwiązaniu problemu.
enum PrivioAuthDiag {
    private static let path = "/tmp/privio_auth.log"
    private static let queue = DispatchQueue(label: "com.privio.authdiag")

    static func log(_ message: String) {
        let line = "\(Date().timeIntervalSince1970) \(message)\n"
        queue.async {
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close()
            } else {
                try? line.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
    }

    @MainActor
    static func snapshot(_ tag: String) -> String {
        func desc(_ w: NSWindow?) -> String {
            guard let w else { return "nil" }
            return "\(type(of: w))#\(w.windowNumber)[\(w.isKeyWindow ? "key" : "")\(w.isMainWindow ? "main" : "")vis=\(w.isVisible)]"
        }
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        let mine = Bundle.main.bundleIdentifier ?? "?"
        return "[\(tag)] active=\(NSApp.isActive) frontmost=\(front)\(front == mine ? "(me)" : "") key=\(desc(NSApp.keyWindow)) main=\(desc(NSApp.mainWindow)) windows=\(NSApp.windows.count)"
    }
}
