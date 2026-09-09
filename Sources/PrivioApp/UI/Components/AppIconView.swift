import SwiftUI
import AppKit
import PrivioCore

/// Ładuje i cache'uje ikony aplikacji (po ścieżce lub bundleID), z sensownym
/// fallbackiem, gdy apka nie jest zainstalowana. Ikony to zasób UI - nie trzymamy
/// ich w modelu (sekcja 5).
@MainActor
final class AppIconCache {
    static let shared = AppIconCache()
    private var cache: [String: NSImage] = [:]

    func icon(bundleID: String, url: URL?) -> NSImage? {
        if let cached = cache[bundleID] { return cached }

        let workspace = NSWorkspace.shared
        var image: NSImage?
        if let url, FileManager.default.fileExists(atPath: url.path) {
            image = workspace.icon(forFile: url.path)
        }
        if image == nil, let resolved = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            image = workspace.icon(forFile: resolved.path)
        }
        if let image { cache[bundleID] = image }
        return image
    }
}

/// Kwadratowa ikona apki z zaokrągleniem; fallback = symbol SF na tle marki.
struct AppIconView: View {
    let bundleID: String
    let url: URL?
    var size: CGFloat = 40

    init(app: ProtectedApp, size: CGFloat = 40) {
        self.bundleID = app.bundleIdentifier
        self.url = app.applicationURL
        self.size = size
    }

    init(installed: InstalledApp, size: CGFloat = 40) {
        self.bundleID = installed.bundleIdentifier
        self.url = installed.url
        self.size = size
    }

    var body: some View {
        Group {
            if let nsImage = AppIconCache.shared.icon(bundleID: bundleID, url: url) {
                Image(nsImage: nsImage).resizable().interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(PrivioGradient.brand)
                    .overlay(
                        FAIcon("app.dashed", size: size * 0.5)
                            .foregroundStyle(.white.opacity(0.9)))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}
