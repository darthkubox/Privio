import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Rejestruje pełny skrót klawiaturowy bez listy gotowych kombinacji.
struct ShortcutRecorderField: View {
    let identifier: String?
    var allowsClearing = false
    var conflictingIdentifier: String?
    let onChange: (String?) -> Void

    @State private var isRecording = false
    @State private var error: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                if allowsClearing, identifier != nil {
                    Button { onChange(nil); error = nil } label: {
                        FAIcon("xmark.circle.fill")
                            .foregroundStyle(Color.privioTextTertiary)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    isRecording = true
                    error = nil
                } label: {
                    Text(isRecording ? "Press shortcut…" : Self.display(identifier))
                        .font(.privioSystem(size: 12, weight: .medium).monospaced())
                        .foregroundStyle(isRecording ? Color.privioPrimary : Color.privioTextPrimary)
                        .frame(minWidth: 92)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.privioSurface))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
                            isRecording ? Color.privioPrimary : Color.privioSeparator))
                }
                .buttonStyle(.plain)
            }
            if let error {
                Text(error).font(.privioSystem(size: 10.5)).foregroundStyle(Color.privioDanger)
            }
        }
        .background(ShortcutCaptureView(
            isRecording: $isRecording,
            onKeyDown: { accept($0) },
            onModifierChord: { acceptModifierChord($0) }
        ))
    }

    private func accept(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { isRecording = false; return }
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        guard !Self.modifierKeyCodes.contains(event.keyCode) else { return }
        guard Self.keyCount(flags: flags, includesRegularKey: true) <= 4 else {
            error = "Use no more than four keys."
            return
        }
        let value = Self.identifier(keyCode: event.keyCode, flags: flags)
        accept(value)
    }

    private func acceptModifierChord(_ flags: NSEvent.ModifierFlags) {
        guard !flags.isEmpty else { return }
        let value = Self.identifier(flags: flags)
        accept(value)
    }

    private func accept(_ value: String) {
        guard value != conflictingIdentifier else {
            error = "This shortcut is already used by Privio."
            return
        }
        guard !Self.reserved.contains(value) else {
            error = "This shortcut is reserved by macOS."
            return
        }
        guard Self.isAvailable(value, current: identifier) else {
            error = "This shortcut is already used by macOS or another app."
            return
        }
        onChange(value)
        error = nil
        isRecording = false
    }

    private static func keyCount(flags: NSEvent.ModifierFlags, includesRegularKey: Bool) -> Int {
        [NSEvent.ModifierFlags.control, .option, .shift, .command]
            .filter(flags.contains).count + (includesRegularKey ? 1 : 0)
    }

    static func display(_ identifier: String?) -> String {
        guard let identifier else { return NSLocalizedString("Off", comment: "Shortcut disabled") }
        switch identifier {
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
        guard let shortcut = PrivacyModeHotKey.shortcut(identifier) else { return "-" }
        var value = ""
        if shortcut.modifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if shortcut.modifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if shortcut.modifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if shortcut.modifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        value += keyNames[UInt16(shortcut.keyCode)] ?? "#\(shortcut.keyCode)"
        return value
    }

    private static func identifier(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> String {
        (identifierParts(flags: flags) + ["keycode", String(keyCode)]).joined(separator: "-")
    }

    private static func identifier(flags: NSEvent.ModifierFlags) -> String {
        identifierParts(flags: flags).joined(separator: "-")
    }

    private static func identifierParts(flags: NSEvent.ModifierFlags) -> [String] {
        var parts: [String] = []
        if flags.contains(.control) { parts.append("control") }
        if flags.contains(.option) { parts.append("option") }
        if flags.contains(.shift) { parts.append("shift") }
        if flags.contains(.command) { parts.append("command") }
        return parts
    }

    private static func isAvailable(_ identifier: String, current: String?) -> Bool {
        if identifier == current { return true }
        if PrivacyModeHotKey.modifierFlags(identifier) != nil && !identifier.contains("keycode-") {
            return true
        }
        guard let shortcut = PrivacyModeHotKey.shortcut(identifier) else { return false }
        var reference: EventHotKeyRef?
        let id = EventHotKeyID(signature: 0x50525453, id: 99) // PRTS
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id,
                                         GetApplicationEventTarget(), 0, &reference)
        if let reference { UnregisterEventHotKey(reference) }
        return status == noErr
    }

    private static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62]
    private static let reserved: Set<String> = [
        "command-keycode-12",                 // ⌘Q
        "command-keycode-13",                 // ⌘W
        "command-keycode-48",                 // ⌘Tab
        "command-keycode-49",                 // ⌘Space
        "option-command-keycode-53",          // ⌥⌘Esc
        "control-command-keycode-12"          // ⌃⌘Q
    ]
    private static let keyNames: [UInt16: String] = [
        0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",
        12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",
        22:"6",23:"5",24:"=",25:"9",26:"7",27:"-",28:"8",29:"0",30:"]",31:"O",
        32:"U",33:"[",34:"I",35:"P",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",
        43:",",44:"/",45:"N",46:"M",47:".",49:"Space",50:"`",51:"⌫",53:"Esc",
        115:"Home",116:"PgUp",117:"⌦",119:"End",121:"PgDn",123:"←",124:"→",125:"↓",126:"↑"
    ]
}

private struct ShortcutCaptureView: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onKeyDown: (NSEvent) -> Void
    let onModifierChord: (NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> CaptureNSView {
        let view = CaptureNSView()
        view.onKeyDown = onKeyDown
        view.onModifierChord = onModifierChord
        return view
    }
    func updateNSView(_ view: CaptureNSView, context: Context) {
        view.onKeyDown = onKeyDown
        view.onModifierChord = onModifierChord
        if isRecording { DispatchQueue.main.async { view.window?.makeFirstResponder(view) } }
        view.isRecording = isRecording
    }
}

private final class CaptureNSView: NSView {
    var isRecording = false
    var onKeyDown: ((NSEvent) -> Void)?
    var onModifierChord: ((NSEvent.ModifierFlags) -> Void)?
    private var recordedModifiers: NSEvent.ModifierFlags = []
    private static let supportedModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
    override var acceptsFirstResponder: Bool { isRecording }
    override func keyDown(with event: NSEvent) {
        recordedModifiers = []
        onKeyDown?(event)
    }
    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { recordedModifiers = []; return }
        let current = event.modifierFlags.intersection(Self.supportedModifiers)
        if current.isEmpty {
            let chord = recordedModifiers
            recordedModifiers = []
            if !chord.isEmpty { onModifierChord?(chord) }
        } else {
            recordedModifiers.formUnion(current)
        }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return false }
        onKeyDown?(event)
        return true
    }
}
