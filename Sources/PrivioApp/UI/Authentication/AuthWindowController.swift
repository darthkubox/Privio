import AppKit
import PrivioCore

/// Panel, który potrafi zostać oknem kluczowym mimo braku ramki.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Niewidoczna „kotwica fokusu" na czas uwierzytelniania.
///
/// Privio jest aplikacją pomocniczą (accessory) bez stałego okna, a macOS nie
/// nadaje aktywności/fokusu aplikacji bez żadnego okna - przez co systemowy
/// prompt Touch ID gubił fokus. Ten kontroler pokazuje malutkie, praktycznie
/// niewidoczne okno‑klucz, dzięki czemu Privio staje się aktywne i systemowy
/// prompt dostaje fokus. Nie pokazujemy żadnego widocznego UI - widać tylko
/// systemowy prompt (zgodnie z życzeniem „sam prompt").
@MainActor
final class AuthFocusAnchor {
    private var panel: KeyablePanel?
    /// Licznik zagnieżdżenia: `authorize` prezentuje kotwicę, a niektórzy wołający
    /// (np. pauza stron) też - bez licznika zagnieżdżony `dismiss` gasiłby fokus za wcześnie.
    private var presentCount = 0

    func present() {
        presentCount += 1
        let panel = self.panel ?? makePanel()
        self.panel = panel
        positionAtActiveScreenCenter(panel)
        // Chwilowo .regular: aplikacja pomocnicza (accessory) bez okna nie zawsze
        // daje się aktywować, przez co systemowy prompt gubił fokus. Na czas auth
        // podnosimy politykę, aktywujemy i czynimy kotwicę oknem klucza.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        presentCount = max(0, presentCount - 1)
        guard presentCount == 0 else { return }   // pozostań, dopóki trwa zewnętrzne opakowanie
        panel?.orderOut(nil)
        // Wróć do accessory, jeśli nie ma otwartego okna ustawień (brak ikony w Docku).
        let hasSettingsWindow = NSApp.windows.contains {
            $0.isVisible && $0.canBecomeMain && !($0 is KeyablePanel)
        }
        if !hasSettingsWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func makePanel() -> KeyablePanel {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.alphaValue = 1.0                  // realne okno klucza; 1×1 przezroczyste = niewidoczne
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        return panel
    }

    private func positionAtActiveScreenCenter(_ panel: NSPanel) {
        let screen = NSScreen.screens.first {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        } ?? NSScreen.main
        if let screen {
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX, y: screen.frame.midY))
        }
    }
}
