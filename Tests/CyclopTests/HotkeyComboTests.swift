import Carbon.HIToolbox
import Foundation
import Testing
@testable import Cyclop

/// Разбор строки хоткея из `config.json`. Сама регистрация в системе не
/// тестируется: она требует живого event target и чужих приложений, которые
/// могут держать ту же комбинацию.
struct HotkeyComboTests {

    @Test func defaultComboParses() {
        let combo = HotkeyCenter.Combo.parse("ctrl+alt+space")
        #expect(combo?.keyCode == UInt32(kVK_Space))
        #expect(combo?.modifiers == UInt32(controlKey | optionKey))
        #expect(combo?.display == "⌃⌥Space")
    }

    @Test func modifierOrderAndCaseDoNotMatter() {
        let a = HotkeyCenter.Combo.parse("Shift+CMD+K")
        let b = HotkeyCenter.Combo.parse("cmd+shift+k")
        #expect(a == b)
        #expect(a?.display == "⇧⌘K")
    }

    @Test func symbolsAndSynonymsAreAccepted() {
        let combo = HotkeyCenter.Combo.parse("⌥+⌘+f12")
        #expect(combo?.keyCode == UInt32(kVK_F12))
        #expect(combo?.modifiers == UInt32(optionKey | cmdKey))
        #expect(HotkeyCenter.Combo.parse("option+command+f12") == combo)
    }

    /// Без модификатора клавиша перехватывалась бы у всех приложений сразу.
    @Test func bareKeyIsRefused() {
        #expect(HotkeyCenter.Combo.parse("space") == nil)
        #expect(HotkeyCenter.Combo.parse("k") == nil)
    }

    @Test func unknownKeyOrModifierIsRefused() {
        #expect(HotkeyCenter.Combo.parse("ctrl+banana") == nil)
        #expect(HotkeyCenter.Combo.parse("hyper+k") == nil)
        #expect(HotkeyCenter.Combo.parse("") == nil)
    }

    /// Минус — клавиша, а не разделитель: `cmd+-` должен читаться.
    @Test func minusIsAKeyNotASeparator() {
        #expect(HotkeyCenter.Combo.parse("cmd+-")?.keyCode == UInt32(kVK_ANSI_Minus))
    }
}
