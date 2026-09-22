import AppKit
import Carbon.HIToolbox

/// A parsed key combination. Top-level rather than nested in `HotkeyCenter`
/// so that nothing about it is tied to the main actor: it is parsed in
/// Settings, in tests and at registration alike.
struct HotkeyCombo: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    /// Human-readable, in the order macOS prints them: ⌃⌥⇧⌘.
    let display: String

    /// `cmd+shift+k`, `ctrl+alt+space`, `⌥+⌘+f12` — case does not matter,
    /// neither does the order of the modifiers. At least one modifier is
    /// required: a bare key would swallow that key in every app.
    static func parse(_ text: String) -> HotkeyCombo? {
        let parts = text
            .lowercased()
            .split(whereSeparator: { $0 == "+" || $0 == " " })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard let keyName = parts.last, parts.count >= 2 else { return nil }

        var modifiers: UInt32 = 0
        for part in parts.dropLast() {
            switch part {
            case "cmd", "command", "⌘": modifiers |= UInt32(cmdKey)
            case "ctrl", "control", "⌃": modifiers |= UInt32(controlKey)
            case "alt", "opt", "option", "⌥": modifiers |= UInt32(optionKey)
            case "shift", "⇧": modifiers |= UInt32(shiftKey)
            default: return nil
            }
        }
        guard modifiers != 0, let keyCode = keyCodes[keyName] else { return nil }

        var display = ""
        if modifiers & UInt32(controlKey) != 0 { display += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { display += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { display += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { display += "⌘" }
        display += keyName.count == 1 ? keyName.uppercased() : keyName.capitalized
        return HotkeyCombo(keyCode: keyCode, modifiers: modifiers, display: display)
    }

    /// Virtual key codes name the physical key, so the combination
    /// survives a layout switch: ⌃⌥K is the same key under a Cyrillic
    /// layout, where it prints "л".
    private static let keyCodes: [String: UInt32] = {
        var table: [String: UInt32] = [
            "space": UInt32(kVK_Space), "`": UInt32(kVK_ANSI_Grave), "-": UInt32(kVK_ANSI_Minus),
            "=": UInt32(kVK_ANSI_Equal), "[": UInt32(kVK_ANSI_LeftBracket), "]": UInt32(kVK_ANSI_RightBracket),
            ";": UInt32(kVK_ANSI_Semicolon), "'": UInt32(kVK_ANSI_Quote), ",": UInt32(kVK_ANSI_Comma),
            ".": UInt32(kVK_ANSI_Period), "/": UInt32(kVK_ANSI_Slash), "\\": UInt32(kVK_ANSI_Backslash),
            "f1": UInt32(kVK_F1), "f2": UInt32(kVK_F2), "f3": UInt32(kVK_F3), "f4": UInt32(kVK_F4),
            "f5": UInt32(kVK_F5), "f6": UInt32(kVK_F6), "f7": UInt32(kVK_F7), "f8": UInt32(kVK_F8),
            "f9": UInt32(kVK_F9), "f10": UInt32(kVK_F10), "f11": UInt32(kVK_F11), "f12": UInt32(kVK_F12),
            "f13": UInt32(kVK_F13), "f14": UInt32(kVK_F14), "f15": UInt32(kVK_F15), "f16": UInt32(kVK_F16),
            "f17": UInt32(kVK_F17), "f18": UInt32(kVK_F18), "f19": UInt32(kVK_F19),
        ]
        let letters: [(String, Int)] = [
            ("a", kVK_ANSI_A), ("b", kVK_ANSI_B), ("c", kVK_ANSI_C), ("d", kVK_ANSI_D), ("e", kVK_ANSI_E),
            ("f", kVK_ANSI_F), ("g", kVK_ANSI_G), ("h", kVK_ANSI_H), ("i", kVK_ANSI_I), ("j", kVK_ANSI_J),
            ("k", kVK_ANSI_K), ("l", kVK_ANSI_L), ("m", kVK_ANSI_M), ("n", kVK_ANSI_N), ("o", kVK_ANSI_O),
            ("p", kVK_ANSI_P), ("q", kVK_ANSI_Q), ("r", kVK_ANSI_R), ("s", kVK_ANSI_S), ("t", kVK_ANSI_T),
            ("u", kVK_ANSI_U), ("v", kVK_ANSI_V), ("w", kVK_ANSI_W), ("x", kVK_ANSI_X), ("y", kVK_ANSI_Y),
            ("z", kVK_ANSI_Z),
            ("0", kVK_ANSI_0), ("1", kVK_ANSI_1), ("2", kVK_ANSI_2), ("3", kVK_ANSI_3), ("4", kVK_ANSI_4),
            ("5", kVK_ANSI_5), ("6", kVK_ANSI_6), ("7", kVK_ANSI_7), ("8", kVK_ANSI_8), ("9", kVK_ANSI_9),
        ]
        for (name, code) in letters { table[name] = UInt32(code) }
        return table
    }()
}

/// One system-wide key combination that summons the panel.
///
/// Carbon's `RegisterEventHotKey` is the one way to hear a key press from any
/// app without Accessibility: the system delivers the combination to this
/// process and nothing else about the keyboard is seen. That is what keeps it
/// inside the project's rule of asking for no permissions.
///
/// The combination lives in `config.json` as text — `ctrl+alt+space` — and is
/// parsed by `Combo`. An empty string switches the hotkey off.
@MainActor
final class HotkeyCenter {
    typealias Combo = HotkeyCombo

    var onPress: (() -> Void)?

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private(set) var combo: Combo?

    /// "CYCL" as a four-character code — the tag Carbon hands back with the
    /// event so the handler can tell this registration from any other.
    nonisolated private static let signature: OSType = 0x4359_434C

    /// Registers `text`, replacing whatever was registered before. Returns
    /// false when the text does not parse or the system refused the
    /// combination — typically because another app already holds it.
    @discardableResult
    func install(_ text: String) -> Bool {
        uninstall()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        guard let combo = Combo.parse(trimmed) else {
            NSLog("Cyclop: hotkey \"\(text)\" is not understood — see config.json")
            return false
        }

        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let userData = Unmanaged.passUnretained(self).toOpaque()
            let status = InstallEventHandler(GetApplicationEventTarget(), Self.callback, 1, &spec, userData, &handler)
            guard status == noErr else {
                NSLog("Cyclop: cannot install hotkey handler, status \(status)")
                return false
            }
        }

        let id = EventHotKeyID(signature: Self.signature, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("Cyclop: cannot register hotkey \(combo.display), status \(status)")
            return false
        }
        hotKey = ref
        self.combo = combo
        return true
    }

    func uninstall() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        combo = nil
    }

    /// A C function pointer, so it captures nothing: the instance travels
    /// through `userData`. Carbon delivers application-target events on the
    /// main thread, which is what makes the isolation assumption below hold.
    private static let callback: EventHandlerUPP = { _, event, userData in
        guard let userData, let event else { return noErr }
        var id = EventHotKeyID()
        let status = GetEventParameter(
            event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
            nil, MemoryLayout<EventHotKeyID>.size, nil, &id
        )
        guard status == noErr, id.signature == HotkeyCenter.signature else { return noErr }
        let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
        MainActor.assumeIsolated { center.onPress?() }
        return noErr
    }
}
