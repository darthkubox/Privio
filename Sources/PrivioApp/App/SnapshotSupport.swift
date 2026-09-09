import SwiftUI
import AppKit
import PrivioCore

/// Tryb podglądu offscreen (bez uprawnień do nagrywania ekranu).
///
/// Uruchomienie aplikacji ze zmienną `PRIVIO_SNAPSHOT=/ścieżka.png` (opcjonalnie
/// `PRIVIO_SNAPSHOT_SECTION=activity|settings|general|about|auth`,
/// `PRIVIO_SNAPSHOT_APPEARANCE=dark`) renderuje realny UI do PNG przez
/// `ImageRenderer` i kończy proces. Służy wyłącznie do weryfikacji podczas
/// developmentu - w normalnym uruchomieniu nieaktywny.
@MainActor
final class SnapshotAppDelegate: NSObject, NSApplicationDelegate {
    /// Wszystkie drogi zakończenia aplikacji przechodzą przez bezpieczne
    /// odmontowanie sejfu. `terminateLater` pozwala dokończyć operację asynchroniczną.
    static var vaultTerminationHandler: (@MainActor () async -> Bool)?
    static var suppressMainWindowForVaultLink = false

    /// Zamknięcie okna ustawień NIE zamyka Privio - zostaje w pasku menu (locker
    /// działa dalej). Ikona w Docku znika (accessory) po zamknięciu okna.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillFinishLaunching(_ notification: Notification) {
        let env = ProcessInfo.processInfo.environment
        guard env["PRIVIO_SNAPSHOT"] == nil,
              env["PRIVIO_VAULT_ICON_SNAPSHOT"] == nil,
              env["PRIVIO_ALLOW_DEVELOPMENT_INSTANCE"] != "1",
              let bundleID = Bundle.main.bundleIdentifier else { return }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownURL = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        let ownIsInstalled = ownURL.path == "/Applications/Privio.app"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ownPID }

        if ownIsInstalled {
            // The installed copy is authoritative. Development copies registered
            // by LaunchServices/Xcode must not run a second enforcement engine.
            for other in others where other.bundleURL?.resolvingSymlinksInPath().standardizedFileURL != ownURL {
                _ = other.terminate()
            }
        } else if others.contains(where: {
            $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path == "/Applications/Privio.app"
        }) {
            // A stray DerivedData build launched at login exits before its
            // monitoring, menu-bar item, proxy, or vault lifecycle starts.
            exit(0)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Otwarty arkusz (sheet) trzyma modalną sesję na oknie, która potrafi wstrzymać
        // zamknięcie inicjowane przez Sparkle - aktualizacja „coś robi", ale apka się nie
        // restartuje i nie instaluje. Zamykamy wszystkie arkusze, zanim oddamy sterowanie
        // ścieżce terminacji. (Panel aktualizacji Sparkle to osobne okno, nie arkusz - nie
        // dotyczy go to.)
        for window in sender.windows {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
        }
        guard let handler = Self.vaultTerminationHandler else { return .terminateNow }
        Task { @MainActor in
            let safeToQuit = await handler()
            sender.reply(toApplicationShouldTerminate: safeToQuit)
        }
        return .terminateLater
    }

    /// Znajduje i pokazuje główne okno ustawień przy starcie (kilka prób, bo SwiftUI
    /// tworzy okno sceny asynchronicznie). Ikona w Docku pojawia się wraz z oknem.
    private func showMainWindowOnLaunch(attempt: Int = 0) {
        // NIE aktywuj okna, gdy trwa systemowy prompt Touch ID - aktywacja Privio
        // odbierała front UIAgentowi uwierzytelniania i prompt gasł (auto-odblokowanie
        // po starcie/aktualizacji „gubiło fokus"). Poczekaj, aż prompt się skończy.
        if AppModel.authInProgress {
            PrivioAuthDiag.log("showMainWindowOnLaunch WAIT (auth) attempt=\(attempt)")
            guard attempt < 100 else { return }   // do ~10 s, aż użytkownik dokończy auth
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.showMainWindowOnLaunch(attempt: attempt + 1)
            }
            return
        }
        if let window = NSApp.windows.first(where: {
            $0.canBecomeMain && !($0 is NSPanel) && $0.contentView != nil
        }) {
            PrivioAuthDiag.log("showMainWindowOnLaunch ACTIVATE attempt=\(attempt)")
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        guard attempt < 12 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.showMainWindowOnLaunch(attempt: attempt + 1)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let env = ProcessInfo.processInfo.environment
        if let iconPath = env["PRIVIO_VAULT_ICON_SNAPSHOT"] {
            do {
                try VaultLauncherService.writeIconSnapshot(to: URL(fileURLWithPath: iconPath))
                FileHandle.standardError.write(Data("vault icon written: \(iconPath)\n".utf8))
            } catch {
                FileHandle.standardError.write(Data("vault icon render FAILED: \(error.localizedDescription)\n".utf8))
            }
            exit(0)
        }
        guard let path = env["PRIVIO_SNAPSHOT"] else {
            // Motyw jasny/ciemny wg wyboru użytkownika (Ustawienia → Wygląd).
            AppTheme.apply()
            // Daj systemowi chwilę na dostarczenie URL `privio://vault`. Skrót
            // sejfu ma otworzyć Finder po auth, bez zbędnego okna ustawień.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if Self.suppressMainWindowForVaultLink {
                    Self.suppressMainWindowForVaultLink = false
                } else {
                    self.showMainWindowOnLaunch()
                }
            }
            return
        }

        var seed = PreviewData.sampleState
        // Podgląd sekcji proximity / paska menu: włączony moduł z zaufanym urządzeniem.
        if env["PRIVIO_SNAPSHOT_SECTION"] == "proximity" || env["PRIVIO_SNAPSHOT_SECTION"] == "menubar" {
            seed.configuration.proximity = ProximityConfig(
                enabled: true, trustedDeviceIDs: ["AA-BB-CC-11-22-33"], lockTarget: .screen)
        }
        let service = InProcessEnforcementService(initialState: seed)
        let model = AppModel(service: service, initialState: seed)
        let vault = VaultController(isSnapshot: true)
        let proximity = ProximityController(config: seed.configuration.proximity, isSnapshot: true)
        model.selectedAppID = seed.apps.first?.id

        switch env["PRIVIO_SNAPSHOT_SECTION"] {
        case "activity": model.selectedSection = .activity
        case "settings": model.selectedSection = .settings
        case "about":    model.selectedSection = .about
        case "websites": model.selectedSection = .websites
        case "privacy":  model.selectedSection = .privacyCurtain
        case "vault":    model.selectedSection = .vault
        case "proximity":
            model.selectedSection = .proximity
            model.snapshotOverrideEdition(pro: true)   // podgląd pełnego UI Pro
        default:         model.selectedSection = .protectedApps
        }

        let dark = env["PRIVIO_SNAPSHOT_APPEARANCE"] == "dark"
        let isLicense = env["PRIVIO_SNAPSHOT_SECTION"] == "license"
        let isMenuBar = env["PRIVIO_SNAPSHOT_SECTION"] == "menubar"
        // W podglądzie paska menu udajemy, że wszystkie przykładowe apki są otwarte.
        if isMenuBar {
            model.runningBundleIDsProvider = { Set(model.state.apps.map(\.app.bundleIdentifier)) }
            model.snapshotOverrideEdition(pro: true)   // pokaż wiersz „Blokada po odejściu"
        }
        // Optional height override to capture scrollable content in one snapshot (dev only).
        let baseHeight = Double(env["PRIVIO_SNAPSHOT_HEIGHT"] ?? "") ?? (isLicense ? 680 : 660)
        let size: NSSize = isLicense ? NSSize(width: 900, height: baseHeight)
            : isMenuBar ? NSSize(width: 300, height: Double(env["PRIVIO_SNAPSHOT_HEIGHT"] ?? "") ?? 720)
            : NSSize(width: 980, height: baseHeight)
        let root: AnyView
        if isLicense {
            root = AnyView(LicenseAgreementView(requireAcceptance: true, startDocumentID: env["PRIVIO_SNAPSHOT_DOC"]))
        } else if isMenuBar {
            root = AnyView(MenuBarContent().environment(model).environment(vault).environment(proximity))
        } else {
            root = AnyView(RootView().environment(model).environment(vault).environment(proximity)
                .frame(width: size.width, height: size.height))
        }

        // Renderujemy REALNĄ hierarchię AppKit w oknie offscreen - natywne
        // kontrolki (przełączniki, pola, listy) rysują się poprawnie, bez
        // uprawnień do nagrywania ekranu (inaczej niż ImageRenderer).
        PrivioFonts.registerAll()
        let hosting = NSHostingView(rootView: root.privioFontEnvironment())
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame,
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000)) // poza ekranem
        window.orderBack(nil)

        // Daj SwiftUI kilka obrotów runloopa na layout leniwych list/ScrollView
        // oraz na ustalenie stanu natywnych przełączników (NSSwitch).
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
                FileHandle.standardError.write(Data("snapshot written: \(path)\n".utf8))
            }
        } else {
            FileHandle.standardError.write(Data("snapshot render FAILED\n".utf8))
        }
        exit(0)
    }
}
