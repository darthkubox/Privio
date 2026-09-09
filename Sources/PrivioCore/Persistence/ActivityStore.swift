import Foundation

/// Zapis/odczyt prywatnej historii zdarzeń (sekcja 19) jako JSON w
/// `~/Library/Application Support/Privio/activity.json`. Historia zostaje lokalnie
/// na Macu; nie zawiera treści chronionych aplikacji - tylko metadane stanu.
public struct ActivityStore: Sendable {
    private let fileURL: URL

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Privio", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("activity.json")
    }

    public func load() -> [ActivityEvent] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([ActivityEvent].self, from: data)) ?? []
    }

    public func save(_ events: [ActivityEvent]) {
        do {
            let data = try JSONEncoder().encode(events)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            PrivioLog.persistence.error("Nie udało się zapisać activity.json: \(error.localizedDescription, privacy: .public)")
        }
    }
}
