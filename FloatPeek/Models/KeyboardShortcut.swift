import AppKit
import Carbon
import Foundation

struct KeyboardShortcut: Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32

    @MainActor
    var displayName: String {
        "\(modifierDisplayName)\(keyDisplayName ?? localized("Unknown"))"
    }

    @MainActor
    var isValid: Bool {
        keyDisplayName != nil
    }

    private var modifierDisplayName: String {
        Self.modifierSymbols
            .filter { carbonModifiers & $0.modifier != 0 }
            .map(\.symbol)
            .joined()
    }

    @MainActor
    private var keyDisplayName: String? {
        let keyCode = Int(keyCode)
        if let keyName = Self.keyNames[keyCode] {
            return keyName
        }
        return Self.localizedKeyNameKeys[keyCode].map(localized)
    }

    private static let modifierSymbols: [(modifier: UInt32, symbol: String)] = [
        (UInt32(cmdKey), "⌘"),
        (UInt32(optionKey), "⌥"),
        (UInt32(controlKey), "⌃"),
        (UInt32(shiftKey), "⇧")
    ]

    private static let keyNames: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
    ]

    /// 表示言語に合わせて翻訳するキー名
    private static let localizedKeyNameKeys: [Int: String] = [
        kVK_Space: "Space",
        kVK_Return: "Return",
        kVK_Tab: "Tab",
        kVK_Escape: "Escape"
    ]

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    init?(event: NSEvent) {
        let carbonModifiers = Self.carbonModifiers(from: event.modifierFlags)

        guard carbonModifiers != 0 else {
            return nil
        }

        self.init(keyCode: UInt32(event.keyCode), carbonModifiers: carbonModifiers)
    }

    static func load(
        from userDefaults: PreferencesStoring = AppEnvironment.preferences
    ) -> KeyboardShortcut {
        guard userDefaults.object(forKey: AppSettings.shortcutKeyCodeKey) != nil,
              userDefaults.object(forKey: AppSettings.shortcutModifiersKey) != nil else {
            return AppSettings.defaultShortcut
        }

        return KeyboardShortcut(
            keyCode: UInt32(userDefaults.integer(forKey: AppSettings.shortcutKeyCodeKey)),
            carbonModifiers: UInt32(userDefaults.integer(forKey: AppSettings.shortcutModifiersKey))
        )
    }

    func save(to userDefaults: PreferencesStoring = AppEnvironment.preferences) {
        userDefaults.set(Int(keyCode), forKey: AppSettings.shortcutKeyCodeKey)
        userDefaults.set(Int(carbonModifiers), forKey: AppSettings.shortcutModifiersKey)
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let flagModifiers: [(flag: NSEvent.ModifierFlags, modifier: UInt32)] = [
            (.command, UInt32(cmdKey)),
            (.option, UInt32(optionKey)),
            (.control, UInt32(controlKey)),
            (.shift, UInt32(shiftKey))
        ]
        return flagModifiers
            .filter { flags.contains($0.flag) }
            .reduce(0) { $0 | $1.modifier }
    }
}
