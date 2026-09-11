import Foundation

/// PID alone is insufficient: macOS can reuse it after an application exits.
public struct RecoverySession: Codable, Equatable, Sendable {
    public let pid: Int32
    public let launchedAt: Date

    public init(pid: Int32, launchedAt: Date) {
        self.pid = pid
        self.launchedAt = launchedAt
    }
}

/// The watchdog is idle until it sees Privio. Registering the helper must not
/// implicitly enable the separate "Start at login" preference.
public struct RecoveryPolicy {
    private var observed: RecoverySession?
    private var recovering = false
    private var nextAttempt: TimeInterval = 0
    private var retryDelay: TimeInterval = 2

    public init() {}

    public mutating func shouldRelaunch(running: RecoverySession?,
                                       permittedExit: RecoverySession?,
                                       now: TimeInterval) -> Bool {
        if let running {
            observed = running
            recovering = false
            // Reset crash-loop backoff only after a stable run.
            if now - running.launchedAt.timeIntervalSince1970 >= 30 {
                retryDelay = 2
                nextAttempt = 0
            }
            return false
        }
        if let observed {
            self.observed = nil
            if permittedExit == observed {
                recovering = false
                retryDelay = 2
                nextAttempt = 0
                return false
            }
            recovering = true
            // Preserve backoff if the relaunched app itself immediately crashes.
            nextAttempt = max(nextAttempt, now + 0.75)
        }
        guard recovering, now >= nextAttempt else { return false }
        nextAttempt = now + retryDelay
        retryDelay = min(retryDelay * 2, 30)
        return true
    }
}

/// Session-scoped coordination, not an authorization boundary against the account
/// owner. Only a completed graceful termination writes an exit permit.
public struct RecoveryStore {
    public let directory: URL

    public init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory,
                                                         in: .userDomainMask)[0]
        .appendingPathComponent("Privio/Recovery", isDirectory: true)) {
        self.directory = directory
    }

    public func permitExit(_ session: RecoverySession) throws {
        try write(session, name: "permitted-exit.json")
    }

    public func permittedExit() -> RecoverySession? { read("permitted-exit.json") }

    public struct Heartbeat: Codable {
        public let date: Date
        public let session: RecoverySession?
    }

    public func heartbeat(session: RecoverySession?) throws {
        try write(Heartbeat(date: Date(), session: session), name: "heartbeat.json")
    }

    public func isWatching(_ session: RecoverySession, now: Date = Date()) -> Bool {
        let heartbeat: Heartbeat? = read("heartbeat.json")
        guard let heartbeat, heartbeat.session == session else { return false }
        return (0...5).contains(now.timeIntervalSince(heartbeat.date))
    }

    private func read<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ value: T, name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(value).write(to: directory.appendingPathComponent(name),
                                             options: [.atomic])
    }
}
