import AppKit
import SwiftUI
import PrivioCore

/// Zasłona blokady - DRUGA warstwa ochrony okien chronionych aplikacji.
///
/// Podstawowym mechanizmem jest ukrywanie apki (`NSRunningApplication.hide()`), ale to
/// bywa zawodne: aplikacji w trybie pełnoekranowym (własny Space) publiczne API nie
/// potrafi ukryć, a przy dużym obciążeniu okno może migotać zanim zniknie. Wtedy prompt
/// Touch ID pojawiał się nad czytelną treścią. Ten kontroler rysuje nad oknami takich
/// apek nieprzezroczystą nakładkę (rozmycie + przyciemnienie + znak Privio), więc treść
/// pozostaje zakryta aż do udanego uwierzytelnienia - niezależnie od tego, czy `hide()`
/// zadziałało.
///
/// W przeciwieństwie do sytuacyjnej `PrivacyCurtainController`:
/// - sterowany STANEM blokady (`LockCoverPolicy`), nie tym, co jest na wierzchu,
/// - nakładka jest nieprzepuszczalna dla myszy (blokuje interakcję z nieukrytym oknem),
/// - NIE ma żadnej drogi odsłonięcia (brak hold-reveal / plakietki) - to zabezpieczenie,
///   które nie może być zdejmowalne przed uwierzytelnieniem. Jedyny przycisk („Unlock")
///   wywołuje systemowy prompt Touch ID/hasła - przydatne, gdy prompt zgubił się pod oknami.
///
/// Geometria okien pochodzi z `WindowGeometry` (tylko pozycja + PID, bez obrazów okien) -
/// bez uprawnień Screen Recording / Accessibility.
@MainActor
final class LockCoverController {
    private var bundleIDsToCover: Set<String> = []
    private var windows: [LockCoverWindow] = []
    private var tickTimer: Timer?
    /// Wywoływane przyciskiem „Unlock" z bundleID zakrytej apki.
    var onUnlock: ((String) -> Void)?

    /// Aktualizuje zasłonę na podstawie migawki stanu enforcement.
    func update(with state: EnforcementState) {
        bundleIDsToCover = LockCoverPolicy.bundleIDsToCover(state)
        if bundleIDsToCover.isEmpty {
            stopTracking()
            teardownWindows()
        } else {
            startTracking()
            refresh()
        }
    }

    // MARK: - Śledzenie geometrii (ruch/rozmiar okien i zmiana Space nie mają notyfikacji)

    private func startTracking() {
        guard tickTimer == nil else { return }
        let timer = Timer(timeInterval: 0.10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopTracking() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func refresh() {
        reconcile(to: targetFrames())
        // NIE wypychaj nakładek na front, gdy trwa systemowy prompt Touch ID - `order
        // FrontRegardless` co 0,10 s wypychało proces Privio na front i ODBIERAŁO front
        // promptowi (gasł ~0,5 s po pojawieniu). Nakładki i tak są już na wierzchu sprzed
        // auth, więc zablokowana treść pozostaje zakryta; wznawiamy po zakończeniu auth.
        guard !AppModel.authInProgress else { return }
        if !windows.isEmpty { PrivioAuthDiag.log("LockCover orderFront x\(windows.count)") }
        for window in windows { window.orderFrontRegardless() }
    }

    /// Ramki wszystkich widocznych okien apek, które trzeba zakryć (może być wiele apek),
    /// razem z bundleID właściciela (dla przycisku „Unlock").
    private func targetFrames() -> [(bundleID: String, frame: NSRect)] {
        guard !bundleIDsToCover.isEmpty else { return [] }
        var targets: [(bundleID: String, frame: NSRect)] = []
        for bundleID in bundleIDsToCover.sorted() {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
                targets += WindowGeometry.windowFrames(pid: app.processIdentifier).map { (bundleID, $0) }
            }
        }
        return targets
    }

    private func reconcile(to targets: [(bundleID: String, frame: NSRect)]) {
        guard !targets.isEmpty else { teardownWindows(); return }
        if windows.map(\.bundleID) != targets.map(\.bundleID) {
            teardownWindows()
            windows = targets.map { target in
                LockCoverWindow(frame: target.frame, bundleID: target.bundleID) { [weak self] in
                    self?.onUnlock?(target.bundleID)
                }
            }
        } else {
            for (window, target) in zip(windows, targets) where window.frame != target.frame {
                window.setFrame(target.frame, display: false)
            }
        }
    }

    private func teardownWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

// MARK: - Okno nakładki

@MainActor
private final class LockCoverWindow: NSPanel {
    let bundleID: String

    init(frame: NSRect, bundleID: String, onUnlock: @escaping () -> Void) {
        self.bundleID = bundleID
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // W przeciwieństwie do Zasłony prywatności NIE przepuszczamy kliknięć: gdy okno
        // nie zostało ukryte, nakładka blokuje też interakcję z jego treścią.
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = LockCoverContentView(onUnlock: onUnlock)
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Treść nakładki: rozmycie + mocne przyciemnienie + znak Privio

@MainActor
private final class LockCoverContentView: NSView {
    private let effectView = NSVisualEffectView()
    private let dim = NSView()
    private let badge: FirstMouseHostingView<LockCoverBadge>

    init(onUnlock: @escaping () -> Void) {
        badge = FirstMouseHostingView(rootView: LockCoverBadge(onUnlock: onUnlock))
        super.init(frame: .zero)
        wantsLayer = true

        effectView.material = .hudWindow           // ciemne, wyraźne rozmycie treści za oknem
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.autoresizingMask = [.width, .height]
        addSubview(effectView)

        // Mocne przyciemnienie NA rozmyciu - treść ma być nieczytelna, nie tylko rozmyta.
        dim.wantsLayer = true
        dim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.68).cgColor
        dim.autoresizingMask = [.width, .height]
        addSubview(dim)

        badge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badge)
        NSLayoutConstraint.activate([
            badge.centerXAnchor.constraint(equalTo: centerXAnchor),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { false }

    override func layout() {
        super.layout()
        effectView.frame = bounds
        dim.frame = bounds
    }
}

/// Panel nakładki nigdy nie staje się kluczowy, więc każde kliknięcie jest „pierwszym" -
/// bez tego pierwsze kliknięcie w „Unlock" mogłoby zostać połknięte.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Znak Privio + „Zablokowane" + „Odblokuj"

/// Wewnętrzne (nie `private`), by snapshot mode mógł je wyrenderować (`lockcover`).
struct LockCoverBadge: View {
    let onUnlock: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            PrivioLogo(fill: .solid(.white))
                .frame(width: 60, height: 60 / PrivioLogoGeometry.aspect)
                .opacity(0.95)
            Text("Locked")
                .font(.privioSystem(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
            // Ponownie wywołuje systemowy prompt (np. gdy zgubił się pod oknami).
            Button(action: onUnlock) {
                Label("Unlock", fa: "touchid")
                    .font(.privioSystem(size: 13, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
            }
            .buttonStyle(LockCoverButtonStyle())
            .padding(.top, 4)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .accessibilityElement(children: .combine)
    }
}

/// Własny styl: panel nakładki nigdy nie jest kluczowy, a `.borderedProminent` w oknie
/// niekluczowym traci kolor akcentu i wygląda na nieaktywny.
private struct LockCoverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(Capsule().fill(Color.privioPrimary.opacity(configuration.isPressed ? 0.75 : 1)))
            .contentShape(Capsule())
    }
}
