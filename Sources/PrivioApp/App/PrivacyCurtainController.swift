import AppKit
import CoreImage
import CoreGraphics
import QuartzCore
import PrivioCore

/// Zasłona prywatności (Privacy Curtain) - osobny, sytuacyjny moduł niezależny od
/// blokady Touch ID. Rysuje nieinteraktywne nakładki:
/// - `.spotlight` - rozmycie + przyciemnienie treści z „latarką" wokół kursora
///   (regulowany rozmiar i kształt) odsłaniającą ostry, jasny obszar,
/// - `.tint`      - przyciemnienie + winieta obniżająca kontrast na brzegach (utrudnia podglądanie z boku),
/// - `.blur`      - samo systemowe rozmycie treści.
///
/// Zakres:
/// - `.fullScreen`     - jedna nakładka na każdy ekran (cały ekran),
/// - `.protectedApps`  - nakładki tylko na oknach aplikacji chronionej Touch ID/hasłem, gdy jest na wierzchu.
///
/// Nakładki przepuszczają kliknięcia (`ignoresMouseEvents`), więc chronione aplikacje pozostają
/// używalne. Skonfigurowany skrót chwilowego odsłonięcia chowa zasłonę na czas przytrzymania.
///
/// Dla zakresu okien używa TYLKO geometrii z `CGWindowListCopyWindowInfo` (pozycja + PID właściciela),
/// bez obrazów okien - nie wymaga uprawnień Screen Recording ani Accessibility. Ruch kursora śledzi
/// `NSEvent.mouseLocation` + globalny monitor myszy (monitory myszy nie wymagają Accessibility).
@MainActor
final class PrivacyCurtainController {
    private var enabled = false
    private var mode: PrivacyCurtainMode = .blur
    private var scope: PrivacyCurtainScope = .protectedApps
    private var intensity: Double = 0.85
    private var spotlightRadius: Double = 180
    private var spotlightShape: PrivacyCurtainSpotlightShape = .circle
    private var protectedBundleIDs: Set<String> = []

    private var windows: [CurtainWindow] = []
    private var tickTimer: Timer?
    private var mouseMonitor: Any?
    private var lastCursorUpdate: TimeInterval = 0
    private var hintText: String = ""
    private var holdRevealShortcut = "option-command"
    private var explicitHoldReveal = false
    private(set) var lockedReveal = false

    func update(configuration: AppConfiguration, apps: [ProtectedAppSnapshot]) {
        enabled = configuration.privacyModeEnabled
        mode = configuration.privacyCurtainMode
        scope = configuration.privacyCurtainScope
        intensity = configuration.privacyCurtainIntensity.clampedCurtainIntensity()
        spotlightRadius = configuration.privacyCurtainSpotlightRadius.clampedSpotlightRadius()
        spotlightShape = configuration.privacyCurtainSpotlightShape
        holdRevealShortcut = configuration.privacyRevealHoldShortcut
        protectedBundleIDs = Set(apps.filter { $0.app.protectionEnabled }.map { $0.app.bundleIdentifier })
        hintText = Self.escapeHint(hold: holdRevealShortcut, off: configuration.privacyModeShortcut)

        if enabled {
            startTracking()
            refresh()
        } else {
            lockedReveal = false
            stopTracking()
            teardownWindows()
        }
    }

    @discardableResult
    func toggleLockedReveal() -> Bool {
        guard enabled else { return false }
        lockedReveal.toggle()
        refresh()
        return lockedReveal
    }

    // MARK: - Reveal

    private var holdRevealActive: Bool {
        if holdRevealShortcut.contains("keycode-") { return explicitHoldReveal }
        guard let required = PrivacyModeHotKey.modifierFlags(holdRevealShortcut) else { return false }
        let current = CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand])
        return current == required
    }

    private var revealActive: Bool { lockedReveal || holdRevealActive }

    func setHoldRevealActive(_ active: Bool) {
        guard explicitHoldReveal != active else { return }
        explicitHoldReveal = active
        refresh()
    }

    // MARK: - Śledzenie stanu

    private func startTracking() {
        if tickTimer == nil {
            // Hold-reveal (⌥⌘), zmiana aktywnej aplikacji i ruch/rozmiar okien nie mają notyfikacji -
            // odświeżamy stan i geometrię na tykaniu.
            let timer = Timer(timeInterval: 0.10, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            RunLoop.main.add(timer, forMode: .common)
            tickTimer = timer
        }
        syncMouseMonitor()
    }

    private func stopTracking() {
        tickTimer?.invalidate()
        tickTimer = nil
        removeMouseMonitor()
    }

    private func syncMouseMonitor() {
        if mode == .spotlight { installMouseMonitor() } else { removeMouseMonitor() }
    }

    private func installMouseMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] _ in
            Task { @MainActor in self?.updateSpotlightCursor() }
        }
    }

    private func removeMouseMonitor() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    private func refresh() {
        syncMouseMonitor()
        reconcile(to: targetFrames())
        // Jak w LockCover: nie wypychaj nakładek na front w trakcie promptu Touch ID,
        // bo `orderFrontRegardless` co tick odbierałby mu front. Zostają na wierzchu sprzed auth.
        let authActive = AppModel.authInProgress
        for window in windows {
            window.apply(mode: mode, intensity: CGFloat(intensity),
                         radius: CGFloat(spotlightRadius), shape: spotlightShape, hint: hintText)
            if !authActive { window.orderFrontRegardless() }
        }
        if mode == .spotlight { updateSpotlightCursor(force: true) }
    }

    /// Docelowe ramki nakładek w globalnych współrzędnych AppKit (lewy-dolny róg).
    private func targetFrames() -> [NSRect] {
        guard enabled, !revealActive else { return [] }
        switch scope {
        case .fullScreen:
            return NSScreen.screens.map { $0.frame }
        case .protectedApps:
            guard let app = NSWorkspace.shared.frontmostApplication,
                  let bundleID = app.bundleIdentifier,
                  protectedBundleIDs.contains(bundleID) else { return [] }
            return WindowGeometry.windowFrames(pid: app.processIdentifier)
        }
    }

    private func reconcile(to frames: [NSRect]) {
        guard !frames.isEmpty else { teardownWindows(); return }
        if windows.count != frames.count {
            teardownWindows()
            windows = frames.map { CurtainWindow(frame: $0) }
        } else {
            for (window, frame) in zip(windows, frames) where window.frame != frame {
                window.setFrame(frame, display: false)
            }
        }
    }

    private func updateSpotlightCursor(force: Bool = false) {
        guard enabled, !revealActive, mode == .spotlight, !windows.isEmpty else { return }
        // Throttle ~60 Hz, żeby nie przegenerowywać maski rozmycia na każdym zdarzeniu myszy.
        let now = CACurrentMediaTime()
        if !force && now - lastCursorUpdate < 0.012 { return }
        lastCursorUpdate = now
        let mouse = NSEvent.mouseLocation
        for window in windows { window.updateSpotlight(globalCursor: mouse) }
    }

    private func teardownWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    // MARK: - Podpowiedź „jak wyłączyć" (zabezpieczenie przed utknięciem)

    private static func shortcutSymbol(_ identifier: String?) -> String? {
        guard let identifier else { return nil }
        switch identifier {
        case "option-command-l": return "⌥⌘L"
        case "control-option-p": return "⌃⌥P"
        case "control-command-l": return "⌃⌘L"
        case "option-command": return "⌥⌘"
        case "control-option": return "⌃⌥"
        case "control-command": return "⌃⌘"
        case "control-shift": return "⌃⇧"
        default: break
        }
        if !identifier.contains("keycode-"), PrivacyModeHotKey.modifierFlags(identifier) != nil {
            let parts = Set(identifier.split(separator: "-").map(String.init))
            var value = ""
            if parts.contains("control") { value += "⌃" }
            if parts.contains("option") { value += "⌥" }
            if parts.contains("shift") { value += "⇧" }
            if parts.contains("command") { value += "⌘" }
            return value
        }
        return ShortcutRecorderField.display(identifier)
    }

    /// Zawsze pokazuje pewną drogę wyjścia: odsłonięcie ⌥⌘, skrót wyłączenia (jeśli ustawiony)
    /// oraz ikonę w pasku menu. Dzięki temu nikt nie utknie w zasłonie.
    private static func escapeHint(hold: String, off: String?) -> String {
        let reveal = shortcutSymbol(hold) ?? "⌥⌘"
        if let symbol = shortcutSymbol(off) {
            let format = NSLocalizedString("%@ reveal · %@ off",
                                           comment: "Escape hint shown in the curtain corner")
            return String(format: format, reveal, symbol)
        }
        let format = NSLocalizedString("%@ reveal · menu off",
                                       comment: "Escape hint shown in the curtain corner (no shortcut)")
        return String(format: format, reveal)
    }
}

// MARK: - Okno nakładki

@MainActor
private final class CurtainWindow: NSPanel {
    private let curtain = CurtainContentView()

    init(frame: NSRect) {
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = curtain
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func apply(mode: PrivacyCurtainMode, intensity: CGFloat,
               radius: CGFloat, shape: PrivacyCurtainSpotlightShape, hint: String) {
        curtain.configure(mode: mode, intensity: intensity, radius: radius, shape: shape, hint: hint)
    }

    /// `globalCursor` w globalnych współrzędnych ekranu (lewy-dolny róg jak `NSEvent.mouseLocation`).
    func updateSpotlight(globalCursor: NSPoint) {
        let local = NSPoint(x: globalCursor.x - frame.minX, y: globalCursor.y - frame.minY)
        curtain.updateCursor(curtain.bounds.contains(local) ? local : nil)
    }
}

// MARK: - Treść nakładki: rozmycie (behindWindow) + rysowane przyciemnienie

@MainActor
private final class CurtainContentView: NSView {
    private let effectView = NSVisualEffectView()
    private let overlay = CurtainOverlayView()
    private let hintPill = NSView()
    private let hintField = NSTextField(labelWithString: "")

    private var mode: PrivacyCurtainMode = .blur
    private var radius: CGFloat = 180
    private var shape: PrivacyCurtainSpotlightShape = .circle
    private var cursor: NSPoint?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        effectView.wantsLayer = true
        effectView.material = .hudWindow           // ciemne, wyraźne rozmycie treści za oknem
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.autoresizingMask = [.width, .height]
        overlay.autoresizingMask = [.width, .height]
        addSubview(effectView)
        addSubview(overlay)                          // przyciemnienie rysowane NA rozmyciu
        setupHintPill()                              // plakietka „jak wyłączyć" - NA wszystkim
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { false }

    /// Zawsze widoczna plakietka w lewym dolnym rogu - zabezpieczenie przed utknięciem w zasłonie.
    private func setupHintPill() {
        hintPill.wantsLayer = true
        hintPill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.62).cgColor
        hintPill.layer?.cornerRadius = 9
        hintPill.layer?.borderWidth = 1
        hintPill.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        hintPill.translatesAutoresizingMaskIntoConstraints = false

        hintField.font = .systemFont(ofSize: 12, weight: .medium)
        hintField.textColor = NSColor.white.withAlphaComponent(0.88)
        hintField.maximumNumberOfLines = 1
        hintField.lineBreakMode = .byTruncatingTail
        hintField.translatesAutoresizingMaskIntoConstraints = false

        hintPill.addSubview(hintField)
        addSubview(hintPill)
        NSLayoutConstraint.activate([
            hintField.leadingAnchor.constraint(equalTo: hintPill.leadingAnchor, constant: 13),
            hintField.trailingAnchor.constraint(equalTo: hintPill.trailingAnchor, constant: -13),
            hintField.topAnchor.constraint(equalTo: hintPill.topAnchor, constant: 7),
            hintField.bottomAnchor.constraint(equalTo: hintPill.bottomAnchor, constant: -7),
            hintPill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            hintPill.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24),
            hintPill.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -48)
        ])
    }

    func configure(mode: PrivacyCurtainMode, intensity: CGFloat,
                   radius: CGFloat, shape: PrivacyCurtainSpotlightShape, hint: String) {
        self.mode = mode
        self.radius = radius
        self.shape = shape
        if mode != .spotlight { cursor = nil }

        hintField.stringValue = hint

        // Rozmycie widoczne w trybie blur i spotlight; ukryte w tint.
        effectView.isHidden = (mode == .tint)
        effectView.frame = bounds
        overlay.frame = bounds
        overlay.configure(mode: mode, intensity: intensity, radius: radius, shape: shape)
        refreshBlurMask()
    }

    func updateCursor(_ point: NSPoint?) {
        guard mode == .spotlight else { return }
        cursor = point
        overlay.updateCursor(point)
        refreshBlurMask()
    }

    override func layout() {
        super.layout()
        effectView.frame = bounds
        overlay.frame = bounds
        refreshBlurMask()
    }

    /// Wycięcie „latarki" bezpośrednio w warstwie efektu. `maskImage` jest przez AppKit
    /// mapowane w przestrzeni obrazu (i na ekranach Retina potrafi przesunąć otwór względem
    /// punktów widoku). CAShapeLayer pracuje w tych samych punktach co overlay i kursor.
    private func refreshBlurMask() {
        guard mode == .spotlight, let cursor, bounds.width > 1, bounds.height > 1 else {
            effectView.maskImage = nil
            effectView.layer?.mask = nil
            return
        }
        effectView.maskImage = nil

        // Rozmycie maski daje naturalne, miękkie przejście: środek pozostaje ostry,
        // a systemowy blur narasta stopniowo na zewnętrznych ~20% promienia.
        let feather = max(18, min(42, radius * 0.18))
        let mask = CAShapeLayer()
        mask.frame = effectView.bounds.insetBy(dx: -feather * 2, dy: -feather * 2)
        mask.fillColor = NSColor.white.cgColor
        mask.fillRule = .evenOdd
        mask.shouldRasterize = true
        mask.rasterizationScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        if let blur = CIFilter(name: "CIGaussianBlur") {
            blur.setValue(feather, forKey: kCIInputRadiusKey)
            mask.filters = [blur]
        }

        let path = CGMutablePath()
        path.addRect(mask.bounds)
        let center = CGPoint(x: cursor.x + feather * 2, y: cursor.y + feather * 2)
        switch shape {
        case .circle:
            path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                       width: radius * 2, height: radius * 2))
        case .ellipse:
            let w = radius * 1.5, h = radius * 0.75
            path.addEllipse(in: CGRect(x: center.x - w, y: center.y - h,
                                       width: w * 2, height: h * 2))
        case .rectangle:
            let w = radius * 1.7, h = radius
            let rect = CGRect(x: center.x - w, y: center.y - h,
                              width: w * 2, height: h * 2)
            let corner = min(w, h) * 0.30
            path.addPath(CGPath(roundedRect: rect, cornerWidth: corner,
                                cornerHeight: corner, transform: nil))
        }
        mask.path = path
        effectView.layer?.mask = mask
    }
}

// MARK: - Rysowane przyciemnienie / tint (z tą samą „latarką")

@MainActor
private final class CurtainOverlayView: NSView {
    private var mode: PrivacyCurtainMode = .blur
    private var intensity: CGFloat = 0.85
    private var radius: CGFloat = 180
    private var shape: PrivacyCurtainSpotlightShape = .circle
    private var cursor: NSPoint?
    private var lastHoleRect: NSRect = .zero

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    func configure(mode: PrivacyCurtainMode, intensity: CGFloat,
                   radius: CGFloat, shape: PrivacyCurtainSpotlightShape) {
        self.mode = mode
        self.intensity = intensity
        self.radius = radius
        self.shape = shape
        if mode != .spotlight { cursor = nil }
        lastHoleRect = .zero
        needsDisplay = true
    }

    func updateCursor(_ point: NSPoint?) {
        guard mode == .spotlight else { return }
        let newHole = point.map { holeBoundingRect(at: $0) } ?? .zero
        cursor = point
        let dirty = lastHoleRect.union(newHole).insetBy(dx: -3, dy: -3)
        lastHoleRect = newHole
        if dirty.isEmpty { needsDisplay = true } else { setNeedsDisplay(dirty) }
    }

    private func holeBoundingRect(at center: NSPoint) -> NSRect {
        switch shape {
        case .circle:
            return NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        case .ellipse:
            let w = radius * 1.5, h = radius * 0.75
            return NSRect(x: center.x - w, y: center.y - h, width: w * 2, height: h * 2)
        case .rectangle:
            let w = radius * 1.7, h = radius * 1.0
            return NSRect(x: center.x - w, y: center.y - h, width: w * 2, height: h * 2)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Przyciemnienie dobrane tak, by w spotlight/blur ROZMYCIE pozostało widoczne (nie czerń).
        let baseAlpha: CGFloat
        switch mode {
        case .blur:      baseAlpha = intensity * 0.28
        case .tint:      baseAlpha = intensity
        case .spotlight: baseAlpha = intensity * 0.55
        }

        let fill: NSColor = (mode == .tint)
            ? NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.05, alpha: baseAlpha)
            : NSColor(white: 0, alpha: baseAlpha)
        fill.setFill()
        ctx.fill(dirtyRect)

        switch mode {
        case .tint:
            drawVignette(ctx: ctx)
        case .spotlight:
            if let cursor {
                ctx.setBlendMode(.destinationOut)
                punchCurtainHole(ctx, center: cursor, radius: radius, shape: shape)
            }
        case .blur:
            break
        }
    }

    /// Winieta: mocniej przyciemnia brzegi, środek (gdzie patrzy osoba z przodu) zostaje jaśniejszy.
    private func drawVignette(ctx: CGContext) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let maxR = CGFloat(hypot(Double(bounds.width), Double(bounds.height))) / 2
        let space = CGColorSpaceCreateDeviceGray()
        let comps: [CGFloat] = [0, 0, 0, intensity * 0.55]
        guard maxR > 0,
              let gradient = CGGradient(colorSpace: space, colorComponents: comps,
                                        locations: [0.0, 1.0], count: 2) else { return }
        ctx.drawRadialGradient(gradient,
                               startCenter: center, startRadius: maxR * 0.32,
                               endCenter: center, endRadius: maxR,
                               options: [.drawsAfterEndLocation])
    }
}

// MARK: - Wspólne rysowanie „latarki" (odejmuje alpha metodą .destinationOut)

/// Wycina miękką „latarkę" danego kształtu. Kontekst musi mieć ustawiony `.destinationOut`.
@MainActor
private func punchCurtainHole(_ ctx: CGContext, center: CGPoint, radius: CGFloat,
                              shape: PrivacyCurtainSpotlightShape) {
    switch shape {
    case .circle:
        if let gradient = softHoleGradient() {
            ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                   endCenter: center, endRadius: radius,
                                   options: [.drawsBeforeStartLocation])
        }
    case .ellipse:
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.scaleBy(x: 1.5, y: 0.75)
        if let gradient = softHoleGradient() {
            ctx.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0,
                                   endCenter: .zero, endRadius: radius,
                                   options: [.drawsBeforeStartLocation])
        }
        ctx.restoreGState()
    case .rectangle:
        let w = radius * 1.7, h = radius * 1.0
        let rect = CGRect(x: center.x - w, y: center.y - h, width: w * 2, height: h * 2)
        let corner = Swift.min(w, h) * 0.30
        let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fillPath()
    }
}

/// Gradient odejmujący alpha: pełny w środku, miękko znikający w zewnętrznych ~30% promienia.
private func softHoleGradient() -> CGGradient? {
    let space = CGColorSpaceCreateDeviceGray()
    let comps: [CGFloat] = [1, 1,  1, 1,  0, 0]   // (biel, alpha) w skali szarości
    return CGGradient(colorSpace: space, colorComponents: comps,
                      locations: [0.0, 0.70, 1.0], count: 3)
}
