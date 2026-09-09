import SwiftUI
import AppKit
import PrivioCore

@main
struct PrivioApp: App {
    @NSApplicationDelegateAdaptor(SnapshotAppDelegate.self) private var snapshotDelegate
    @State private var model: AppModel
    @State private var vault: VaultController
    @State private var proximity: ProximityController

    init() {
        // Kroje marki (Nunito + Font Awesome) muszą być zarejestrowane, zanim
        // jakikolwiek widok policzy metrykę tekstu/ikon.
        PrivioFonts.registerAll()

        // Język UI musi być ustawiony ZANIM cokolwiek wczyta tekst (sekcja Ustawienia).
        AppLanguage.applyStartupOverride()

        // FAZA 2-3: persystencja + realny monitoring aktywacji. Enforcement ładuje
        // apki z dysku, obserwuje NSWorkspace i ukrywa zablokowane apki. Ten sam
        // typ `service` (seam) - reszta aplikacji bez zmian.
        let store = ConfigStore()
        let initialState = EnforcementState.loaded(from: store)
        let selfID = Bundle.main.bundleIdentifier ?? "com.privio.Privio"
        let catalog = ApplicationCatalog(excludedBundleIDs: [selfID])

        // W trybie snapshot (render offscreen) nie uruchamiamy monitoringu ani
        // ukrywania - to tylko podgląd UI.
        let isSnapshot = ProcessInfo.processInfo.environment["PRIVIO_SNAPSHOT"] != nil
        let failedAttemptRecorder: FailedAttemptRecording? = isSnapshot
            ? nil
            : CameraFailedAttemptRecorder()
        // Proxy stron: język i wersja aplikacji są stałe na czas życia procesu
        // (zmiana języka wymaga restartu), więc ustawiamy je raz przy konstrukcji -
        // rozszerzenie odczytuje je z /privio/config (tryb „Auto" i UI).
        let webProxy: WebProxyServer? = isSnapshot ? nil : WebProxyServer()
        webProxy?.updateLanguage(AppLanguage.effectiveCode)
        webProxy?.updateAppVersion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
        let service = InProcessEnforcementService(
            store: store,
            activityStore: isSnapshot ? nil : ActivityStore(),
            monitor: isSnapshot ? nil : WorkspaceAppMonitor(),
            systemMonitor: isSnapshot ? nil : WorkspaceSystemEventMonitor(),
            controller: isSnapshot ? nil : WorkspaceAppController(),
            authenticator: isSnapshot ? nil : LocalAuthenticator(),
            scheduler: isSnapshot ? nil : RealInactivityScheduler(),
            failedAttemptRecorder: failedAttemptRecorder,
            // Blokowanie stron przez lokalne proxy + PAC z fallbackiem DIRECT: gdy
            // Privio nie żyje, chronione strony łączą się bezpośrednio (fail‑open),
            // więc awaria apki nigdy nie zrywa internetu (SystemWebProxy).
            webProxy: webProxy,
            initialState: initialState)

        let vault = VaultController(isSnapshot: isSnapshot)
        let model = AppModel(service: service, initialState: initialState, catalog: catalog)

        // Moduł „Blokada po odejściu" (Pro). Kontroler żyje w warstwie aplikacji, bo
        // cel „apki Privio" obejmuje też sejf, a „ekran" dotyka systemu. Config płynie
        // z enforcementu przez hak `onProximityConfig`; akcje wykonawcze wstrzykujemy tu.
        let proximity = ProximityController(config: initialState.configuration.proximity,
                                            isSnapshot: isSnapshot)
        proximity.onLockProtectedApps = { [weak model] in model?.lockAllForProximity() }
        proximity.onLockVault = { [weak vault] in Task { _ = await vault?.lock() } }
        proximity.onPersistPaused = { [weak model] paused in
            model?.setProximityConfig { $0.paused = paused }
        }
        model.onProximityConfig = { [weak proximity] config in proximity?.update(config: config) }

        _model = State(initialValue: model)
        _vault = State(initialValue: vault)
        _proximity = State(initialValue: proximity)
        SnapshotAppDelegate.vaultTerminationHandler = { await vault.prepareForTermination() }
    }

    var body: some Scene {
        Window("Privio", id: "main") {
            RootView()
                .environment(model)
                .environment(vault)
                .environment(proximity)
                .privioFontEnvironment()
                .frame(minWidth: 900, minHeight: 620)
                .onOpenURL { url in
                    guard url.scheme == "privio", url.host == "vault" else { return }
                    SnapshotAppDelegate.suppressMainWindowForVaultLink = true
                    Task { _ = await vault.unlock(openInFinder: true) }
                }
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))

        MenuBarExtra {
            MenuBarContent()
                .environment(model)
                .environment(vault)
                .environment(proximity)
                .privioFontEnvironment()
        } label: {
            // Znak Privio (template, biały/czarny wg paska); czerwona kropka,
            // gdy ochrona jest wyłączona (jak w AdGuard).
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Etykieta w pasku menu: znak Privio; gdy ochrona wyłączona - z czerwoną kropką.
/// Obserwuje model (reaktywnie) oraz schemat kolorów (adaptacja jasny/ciemny).
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: MenuBarIcon.image(active: model.state.protectionActive,
                                         dark: scheme == .dark))
            // Rozszerzenie poprosiło o otwarcie panelu (przycisk „Otwórz ustawienia").
            // To zawsze żywy widok, więc reagujemy nawet przy zamkniętym oknie.
            // Prezentacja jest bramkowana Touch ID (unlockMainWindow → openPrivio).
            .onChange(of: model.panelOpenSignal) { _, _ in
                Task {
                    guard await model.unlockMainWindow() else { return }
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                }
            }
    }
}

/// Znak Privio dla paska menu.
/// - ochrona ON → obraz template (system renderuje biało/czarno wg paska),
/// - ochrona OFF → obraz kolorowy: logo + wypełniona czerwona kropka (jak AdGuard).
enum MenuBarIcon {
    static func image(active: Bool, dark: Bool) -> NSImage {
        active ? templateImage : offImage(dark: dark)
    }

    private static func drawLogo(in rect: NSRect, color: NSColor) {
        let logoSize = NSSize(width: rect.height * PrivioSmallLogoGeometry.aspect,
                              height: rect.height)
        let swiftPath = PrivioSmallLogoGeometry.path(in: logoSize)
        let bezier = NSBezierPath(cgPath: swiftPath.cgPath)
        let translation = AffineTransform(translationByX: rect.minX, byY: rect.minY)
        bezier.transform(using: translation)
        bezier.lineWidth = logoSize.width * PrivioSmallLogoGeometry.designLineWidthRatio
        bezier.lineCapStyle = .round
        bezier.lineJoinStyle = .round
        color.setStroke()
        bezier.stroke()
    }

    static let templateImage: NSImage = {
        let image = NSImage(size: NSSize(width: 14, height: 20), flipped: true) { rect in
            drawLogo(in: rect, color: .black)   // kolor nieistotny dla template
            return true
        }
        image.isTemplate = true
        return image
    }()

    private static func offImage(dark: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 20), flipped: true) { rect in
            drawLogo(in: rect, color: dark ? .white : .black)
            // Mała czerwona kropka w prawym‑dolnym rogu (jak w AdGuard).
            let d = rect.width * 0.30
            let inset = rect.width * 0.02
            let dot = NSRect(x: rect.maxX - d - inset, y: rect.maxY - d - inset, width: d, height: d)
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
