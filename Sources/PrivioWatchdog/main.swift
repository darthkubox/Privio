import AppKit
import os

// launchd owns this process, independently of Privio's UI process. It never
// authenticates, unlocks apps, or opens files in the vault.
let logger = Logger(subsystem: "com.privio.Privio", category: "recovery")
var appURL = URL(fileURLWithPath: "/Applications/Privio.app")
var store = RecoveryStore()
#if DEBUG
// Isolated integration tests cannot touch the installed app or its preferences.
if CommandLine.arguments.count == 5, CommandLine.arguments[1] == "--test-app",
   CommandLine.arguments[3] == "--test-state" {
    appURL = URL(fileURLWithPath: CommandLine.arguments[2])
    store = RecoveryStore(directory: URL(fileURLWithPath: CommandLine.arguments[4]))
}
#endif
let bundleID = Bundle(url: appURL)?.bundleIdentifier ?? "com.privio.Privio"
var policy = RecoveryPolicy()
var opening = false
var lastHeartbeat = Date.distantPast

func tick() {
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .first { !$0.isTerminated && $0.bundleURL?.resolvingSymlinksInPath() == appURL.resolvingSymlinksInPath() }
    let session = running.flatMap { app in
        app.launchDate.map { RecoverySession(pid: app.processIdentifier, launchedAt: $0) }
    }
    let now = Date()
    if session != nil, now.timeIntervalSince(lastHeartbeat) >= 2 {
        do { try store.heartbeat(session: session) }
        catch { logger.error("Cannot write recovery heartbeat: \(error.localizedDescription, privacy: .public)") }
        lastHeartbeat = now
    }
    guard !opening, policy.shouldRelaunch(running: session, permittedExit: store.permittedExit(),
                                         now: now.timeIntervalSince1970) else { return }
    // No launch after uninstall, and always use the installed URL rather than
    // LaunchServices' bundle-ID lookup (which can select a DerivedData copy).
    guard FileManager.default.fileExists(atPath: appURL.path) else { return }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    configuration.addsToRecentItems = false
    configuration.arguments = ["--privio-recovered"]
    opening = true
    logger.notice("Restarting Privio after an unexpected exit")
    NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
        DispatchQueue.main.async {
            opening = false
            if let error {
                logger.error("Recovery launch failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in tick() }
tick()
RunLoop.main.run()
