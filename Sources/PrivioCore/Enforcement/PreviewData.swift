import Foundation

/// Przykładowe dane odwzorowujące mockup (Signal / Photos / Notes / Telegram).
///
/// FAZA 1: używane do zasilenia UI, by okno było wierne projektowi graficznemu
/// jeszcze zanim podłączymy realny katalog aplikacji i persystencję (Faza 2).
/// Wykorzystywane też w podglądach SwiftUI.
public enum PreviewData {

    public static func sampleApp(
        bundleID: String,
        name: String,
        path: String,
        enabled: Bool = true,
        lock: TimeInterval? = 120,
        quit: TimeInterval? = 900
    ) -> ProtectedApp {
        ProtectedApp(
            bundleIdentifier: bundleID,
            displayName: name,
            applicationURL: URL(fileURLWithPath: path),
            protectionEnabled: enabled,
            lockAfterInactivity: lock,
            quitAfterInactivity: quit
        )
    }

    public static var sampleApps: [ProtectedAppSnapshot] {
        [
            ProtectedAppSnapshot(
                app: sampleApp(bundleID: "org.whispersystems.signal-desktop",
                               name: "Signal", path: "/Applications/Signal.app",
                               lock: 120, quit: 900),
                status: .locked),
            ProtectedAppSnapshot(
                app: sampleApp(bundleID: "com.apple.Photos",
                               name: "Photos", path: "/System/Applications/Photos.app",
                               lock: 300, quit: nil),
                status: .unlocked),
            ProtectedAppSnapshot(
                app: sampleApp(bundleID: "com.apple.Notes",
                               name: "Notes", path: "/System/Applications/Notes.app",
                               lock: 60, quit: nil),
                status: .locked),
            ProtectedAppSnapshot(
                app: sampleApp(bundleID: "ru.keepcoder.Telegram",
                               name: "Telegram", path: "/Applications/Telegram.app",
                               lock: 120, quit: 1800),
                status: .locked),
        ]
    }

    public static var sampleActivity: [ActivityEvent] {
        let now = Date()
        return [
            ActivityEvent(date: now.addingTimeInterval(-120), kind: .unlocked,
                          reason: .authentication, appDisplayName: "Signal",
                          bundleIdentifier: "org.whispersystems.signal-desktop"),
            ActivityEvent(date: now.addingTimeInterval(-420), kind: .locked,
                          reason: .inactivity, appDisplayName: "Signal",
                          bundleIdentifier: "org.whispersystems.signal-desktop"),
            ActivityEvent(date: now.addingTimeInterval(-1800), kind: .locked,
                          reason: .screenLock, appDisplayName: "Photos",
                          bundleIdentifier: "com.apple.Photos"),
            ActivityEvent(date: now.addingTimeInterval(-5400), kind: .quit,
                          reason: .inactivity, appDisplayName: "Signal",
                          bundleIdentifier: "org.whispersystems.signal-desktop"),
        ]
    }

    public static var sampleWebTargets: [WebTargetSnapshot] {
        [
            WebTargetSnapshot(target: WebTarget(domain: "twitter.com"), status: .locked),
            WebTargetSnapshot(target: WebTarget(domain: "news.ycombinator.com"), status: .unlocked),
            WebTargetSnapshot(target: WebTarget(domain: "reddit.com"), status: .locked),
        ]
    }

    public static var sampleState: EnforcementState {
        EnforcementState(
            protectionActive: true,
            apps: sampleApps,
            webTargets: sampleWebTargets,
            configuration: .default,
            recentActivity: sampleActivity
        )
    }
}
