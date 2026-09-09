import AppKit
import Carbon.HIToolbox

/// Globalny skrót oparty o systemowy rejestr Hot Key - nie wymaga uprawnienia
/// Accessibility i działa również, gdy panel Privio jest zamknięty.
@MainActor
final class PrivacyModeHotKey {
    private var hotKey: EventHotKeyRef?
    private var revealHotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var modifierTimer: Timer?
    private var modifierChordActive = false
    private var currentIdentifier: String?
    private var action: (() -> Void)?
    private var revealPressedAction: (() -> Void)?
    private var revealReleasedAction: (() -> Void)?
    private let signature: OSType = 0x5052564D // "PRVM"

    init() {
        var events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return noErr }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil,
                                           &identifier)
            guard status == noErr else { return status }
            let monitor = Unmanaged<PrivacyModeHotKey>.fromOpaque(context).takeUnretainedValue()
            guard identifier.signature == monitor.signature else { return noErr }
            Task { @MainActor in
                if identifier.id == 2 {
                    if GetEventKind(event) == UInt32(kEventHotKeyPressed) { monitor.revealPressedAction?() }
                    else { monitor.revealReleasedAction?() }
                } else if GetEventKind(event) == UInt32(kEventHotKeyPressed) {
                    monitor.action?()
                }
            }
            return noErr
        }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    deinit {
        modifierTimer?.invalidate()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let revealHotKey { UnregisterEventHotKey(revealHotKey) }
        if let handler { RemoveEventHandler(handler) }
    }

    func registerRevealHold(identifier: String?, pressed: @escaping () -> Void,
                            released: @escaping () -> Void) {
        revealPressedAction = pressed
        revealReleasedAction = released
        if let revealHotKey { UnregisterEventHotKey(revealHotKey) }
        revealHotKey = nil
        guard let identifier, let shortcut = Self.shortcut(identifier) else { return }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: signature, id: 2)
        RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id,
                            GetApplicationEventTarget(), 0, &ref)
        revealHotKey = ref
    }

    func register(identifier: String?, action: @escaping () -> Void) {
        self.action = action
        guard identifier != currentIdentifier else { return }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        modifierTimer?.invalidate()
        modifierTimer = nil
        modifierChordActive = false
        currentIdentifier = identifier
        if let identifier, !identifier.contains("keycode-"),
           let requiredFlags = Self.modifierFlags(identifier) {
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    let current = CGEventSource.flagsState(.combinedSessionState)
                        .intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand])
                    let active = current == requiredFlags
                    if active && !self.modifierChordActive { self.action?() }
                    self.modifierChordActive = active
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            modifierTimer = timer
            return
        }
        guard let identifier, let shortcut = Self.shortcut(identifier) else { return }

        let id = EventHotKeyID(signature: signature, id: 1)
        RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id,
                            GetApplicationEventTarget(), 0, &hotKey)
    }

    static func shortcut(_ identifier: String) -> (keyCode: UInt32, modifiers: UInt32)? {
        let parts = identifier.split(separator: "-")
        if let marker = parts.firstIndex(of: "keycode"), marker + 1 < parts.count,
           let code = UInt32(parts[marker + 1]) {
            var modifiers: UInt32 = 0
            if parts.contains("control") { modifiers |= UInt32(controlKey) }
            if parts.contains("option") { modifiers |= UInt32(optionKey) }
            if parts.contains("shift") { modifiers |= UInt32(shiftKey) }
            if parts.contains("command") { modifiers |= UInt32(cmdKey) }
            return (code, modifiers)
        }
        switch identifier {
        case "option-command-l":
            return (UInt32(kVK_ANSI_L), UInt32(optionKey | cmdKey))
        case "control-option-p":
            return (UInt32(kVK_ANSI_P), UInt32(controlKey | optionKey))
        case "control-command-l":
            return (UInt32(kVK_ANSI_L), UInt32(controlKey | cmdKey))
        case "option-command-p":
            return (UInt32(kVK_ANSI_P), UInt32(optionKey | cmdKey))
        case "control-option-r":
            return (UInt32(kVK_ANSI_R), UInt32(controlKey | optionKey))
        case "control-command-r":
            return (UInt32(kVK_ANSI_R), UInt32(controlKey | cmdKey))
        case "control-shift-r":
            return (UInt32(kVK_ANSI_R), UInt32(controlKey | shiftKey))
        default:
            return nil
        }
    }

    static func modifierFlags(_ identifier: String) -> CGEventFlags? {
        let parts = Set(identifier.split(separator: "-").map(String.init))
        guard !parts.isEmpty,
              parts.isSubset(of: ["control", "option", "shift", "command"]) else { return nil }
        var flags: CGEventFlags = []
        if parts.contains("control") { flags.insert(.maskControl) }
        if parts.contains("option") { flags.insert(.maskAlternate) }
        if parts.contains("shift") { flags.insert(.maskShift) }
        if parts.contains("command") { flags.insert(.maskCommand) }
        return flags
    }
}
