import Foundation

struct VaultNote: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var body: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), title: String = "New note", body: String = "", date: Date = Date()) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = date
        self.updatedAt = date
    }
}

struct VaultFileItem: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64?
    let modifiedAt: Date?

    var id: URL { url }
}

enum VaultStatus: Equatable, Sendable {
    case notCreated
    case locked
    case working(String)
    case unlocked(VaultMount)

    var isUnlocked: Bool {
        if case .unlocked = self { return true }
        return false
    }
}

struct VaultPreferences: Equatable, Sendable {
    var lockOnScreenLock: Bool
    var lockOnSleep: Bool
    /// 0 = brak blokady czasowej; poza tym czas od odblokowania.
    var autoLockMinutes: Int

    static let defaults = VaultPreferences(lockOnScreenLock: true, lockOnSleep: true, autoLockMinutes: 0)
}
