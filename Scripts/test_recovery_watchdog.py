#!/usr/bin/env python3
"""macOS smoke test using a disposable GUI app and a temporary launchd job.

Usage: python3 Scripts/test_recovery_watchdog.py .build/recovery-check/Build/Products/Debug/PrivioWatchdog
Requires a logged-in GUI session. Never launches or terminates the installed Privio.
"""
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import sys
import tempfile
import time
import uuid

repo = Path(__file__).resolve().parent.parent
watchdog = Path(sys.argv[1]).resolve()
assert watchdog.is_file(), watchdog


def wait_for(predicate, description, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = predicate()
        if result:
            return result
        time.sleep(0.1)
    raise AssertionError(description)


with tempfile.TemporaryDirectory(prefix="PrivioRecoveryTest-") as temporary:
    root = Path(temporary)
    app = root / "RecoveryFixture.app"
    contents = app / "Contents"
    (contents / "MacOS").mkdir(parents=True)
    state = root / "state"
    state.mkdir()
    bundle_id = "com.privio.recoverytest." + uuid.uuid4().hex
    with (contents / "Info.plist").open("wb") as file:
        plistlib.dump({"CFBundleIdentifier": bundle_id, "CFBundleExecutable": "Fixture",
                      "CFBundlePackageType": "APPL", "LSUIElement": True,
                      "RecoveryTestState": str(state)}, file)
    source = root / "main.swift"
    source.write_text('''import AppKit
let app = NSApplication.shared
let directory = URL(fileURLWithPath: Bundle.main.infoDictionary!["RecoveryTestState"] as! String)
let store = RecoveryStore(directory: directory)
@MainActor final class Delegate: NSObject, NSApplicationDelegate {
    let termination = TerminationCoordinator()
    func applicationDidFinishLaunching(_ notification: Notification) {
        try! String(ProcessInfo.processInfo.processIdentifier).write(
            to: directory.appendingPathComponent("pid"), atomically: true, encoding: .utf8)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if termination.isTerminationAuthorized {
            let session = RecoverySession(pid: ProcessInfo.processInfo.processIdentifier,
                                          launchedAt: NSRunningApplication.current.launchDate!)
            try! store.permitExit(session)
            return .terminateNow
        }
        termination.request(authorize: {
            try! Data().write(to: directory.appendingPathComponent("auth-requested"))
            return (try? String(contentsOf: directory.appendingPathComponent("auth-decision"), encoding: .utf8)) == "allow"
        }, prepare: { true }, terminate: { sender.terminate(nil) })
        return .terminateCancel
    }
}
let delegate = MainActor.assumeIsolated { Delegate() }
app.delegate = delegate
signal(SIGTERM, SIG_IGN)
let stop = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
stop.setEventHandler {
    app.terminate(nil)
}
stop.resume()
app.run()
''')
    subprocess.run(["xcrun", "swiftc", str(repo / "Sources/PrivioRecoverySupport/RecoveryPolicy.swift"),
                    str(repo / "Sources/PrivioCore/Security/TerminationCoordinator.swift"),
                    str(source), "-o", str(contents / "MacOS/Fixture")], check=True)
    subprocess.run(["codesign", "-s", "-", str(app)], check=True, capture_output=True)
    label = "com.privio.recoverytest." + uuid.uuid4().hex
    job = f"gui/{os.getuid()}/{label}"
    plist = root / "watchdog.plist"
    with plist.open("wb") as file:
        plistlib.dump({"Label": label, "ProgramArguments": [str(watchdog), "--test-app", str(app),
                       "--test-state", str(state)], "KeepAlive": True, "ThrottleInterval": 1}, file)

    def current_pid():
        try:
            return int((state / "pid").read_text())
        except (FileNotFoundError, ValueError):
            return None

    def watching(pid):
        try:
            session = json.loads((state / "heartbeat.json").read_text()).get("session")
            return session and session["pid"] == pid
        except (FileNotFoundError, ValueError):
            return False

    def is_alive(pid):
        try:
            os.kill(pid, 0)
            return True
        except ProcessLookupError:
            return False

    try:
        subprocess.run(["launchctl", "bootstrap", f"gui/{os.getuid()}", str(plist)], check=True)
        time.sleep(2)
        assert current_pid() is None, "Helper must not start an app before its first manual launch"
        subprocess.run(["open", "-g", str(app)], check=True)
        initial = wait_for(current_pid, "Fixture failed to launch")
        wait_for(lambda: watching(initial), "Watchdog failed to observe fixture")
        started = time.monotonic()
        os.kill(initial, signal.SIGKILL)
        recovered = wait_for(lambda: current_pid() if current_pid() != initial else None,
                             "SIGKILL did not trigger recovery")
        print(f"PASS: SIGKILL recovered with a new PID in {time.monotonic() - started:.2f}s", flush=True)
        wait_for(lambda: watching(recovered), "Recovered fixture was not observed")
        (state / "auth-decision").write_text("deny")
        os.kill(recovered, signal.SIGTERM)
        wait_for(lambda: (state / "auth-requested").exists(), "Quit did not request authentication")
        time.sleep(1)
        assert is_alive(recovered), "Denied authentication closed the app"
        assert not (state / "permitted-exit.json").exists(), "Denied quit disabled the watchdog"
        print("PASS: native quit with denied authentication stays running and keeps watchdog armed", flush=True)
        (state / "auth-decision").write_text("allow")
        # Graceful-exit permit is written by the fixture before SIGTERM completes.
        os.kill(recovered, signal.SIGTERM)
        wait_for(lambda: not is_alive(recovered), "Graceful quit failed")
        time.sleep(4)
        assert current_pid() == recovered and not is_alive(recovered), "Graceful quit relaunched"
        print("PASS: graceful quit remains closed", flush=True)
        subprocess.run(["open", "-g", str(app)], check=True)
        manual = wait_for(lambda: current_pid() if current_pid() != recovered else None,
                          "Manual reopen failed")
        wait_for(lambda: watching(manual), "Manual reopen did not rearm watchdog")
        os.kill(manual, signal.SIGKILL)
        again = wait_for(lambda: current_pid() if current_pid() != manual else None,
                         "Recovery did not rearm after graceful quit")
        print("PASS: reopening rearms recovery; old exit permit does not bypass it", flush=True)
    finally:
        subprocess.run(["launchctl", "bootout", job], capture_output=True)
        pid = current_pid()
        if pid and is_alive(pid):
            (state / "auth-decision").write_text("allow")
            os.kill(pid, signal.SIGTERM)
            wait_for(lambda: not is_alive(pid), "Fixture cleanup failed")
