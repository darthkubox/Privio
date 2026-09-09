import Foundation

/// Zainstalowana aplikacja wykryta na dysku (do przeglądania/wyszukiwania w
/// "Add Application" - sekcja 6).
public struct InstalledApp: Identifiable, Hashable, Sendable {
    public var id: String { bundleIdentifier }
    public let bundleIdentifier: String
    public let displayName: String
    public let url: URL

    public init(bundleIdentifier: String, displayName: String, url: URL) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.url = url
    }
}

/// Skanuje typowe lokalizacje w poszukiwaniu pakietów `.app` (sekcja 6).
/// Nie hardkoduje aplikacji Apple; zwraca wszystko, co ma bundle identifier.
public struct ApplicationCatalog: Sendable {
    private let excludedBundleIDs: Set<String>
    private let locations: [URL]

    public init(excludedBundleIDs: Set<String> = []) {
        self.excludedBundleIDs = excludedBundleIDs
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.locations = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            home.appendingPathComponent("Applications"),
        ]
    }

    /// Synchroniczny skan (I/O). Wołać z tła (`Task.detached`).
    public func scan() -> [InstalledApp] {
        var byBundleID: [String: InstalledApp] = [:]
        let fm = FileManager.default

        for location in locations {
            guard let entries = try? fm.contentsOfDirectory(
                at: location, includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles]) else { continue }

            for url in entries where url.pathExtension == "app" {
                guard let app = installedApp(at: url) else { continue }
                if excludedBundleIDs.contains(app.bundleIdentifier) { continue }
                // Preferuj pierwszą znalezioną (np. /Applications nad /System).
                if byBundleID[app.bundleIdentifier] == nil {
                    byBundleID[app.bundleIdentifier] = app
                }
            }
        }

        return byBundleID.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private func installedApp(at url: URL) -> InstalledApp? {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return nil }
        let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return InstalledApp(bundleIdentifier: bundleID, displayName: name, url: url)
    }
}
