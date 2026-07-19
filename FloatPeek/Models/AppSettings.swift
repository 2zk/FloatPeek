import AppKit
import Carbon
import Foundation

struct AppSettings {
    static let selectedFolderPathKey = "selectedFolderPath"
    static let shortcutKeyCodeKey = "shortcutKeyCode"
    static let shortcutModifiersKey = "shortcutModifiers"
    static let windowFrameKey = "windowFrame"
    static let languageKey = "language"
    static let folderTabsKey = "folderTabs"
    static let selectedFolderTabIDKey = "selectedFolderTabID"

    static let defaultShortcut = KeyboardShortcut(
        keyCode: UInt32(kVK_ANSI_1),
        carbonModifiers: UInt32(cmdKey | shiftKey)
    )
}

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
        var parts: [String] = []

        if carbonModifiers & UInt32(cmdKey) != 0 {
            parts.append("⌘")
        }
        if carbonModifiers & UInt32(optionKey) != 0 {
            parts.append("⌥")
        }
        if carbonModifiers & UInt32(controlKey) != 0 {
            parts.append("⌃")
        }
        if carbonModifiers & UInt32(shiftKey) != 0 {
            parts.append("⇧")
        }

        return parts.joined()
    }

    @MainActor
    private var keyDisplayName: String? {
        switch keyCode {
        case UInt32(kVK_ANSI_A): "A"
        case UInt32(kVK_ANSI_B): "B"
        case UInt32(kVK_ANSI_C): "C"
        case UInt32(kVK_ANSI_D): "D"
        case UInt32(kVK_ANSI_E): "E"
        case UInt32(kVK_ANSI_F): "F"
        case UInt32(kVK_ANSI_G): "G"
        case UInt32(kVK_ANSI_H): "H"
        case UInt32(kVK_ANSI_I): "I"
        case UInt32(kVK_ANSI_J): "J"
        case UInt32(kVK_ANSI_K): "K"
        case UInt32(kVK_ANSI_L): "L"
        case UInt32(kVK_ANSI_M): "M"
        case UInt32(kVK_ANSI_N): "N"
        case UInt32(kVK_ANSI_O): "O"
        case UInt32(kVK_ANSI_P): "P"
        case UInt32(kVK_ANSI_Q): "Q"
        case UInt32(kVK_ANSI_R): "R"
        case UInt32(kVK_ANSI_S): "S"
        case UInt32(kVK_ANSI_T): "T"
        case UInt32(kVK_ANSI_U): "U"
        case UInt32(kVK_ANSI_V): "V"
        case UInt32(kVK_ANSI_W): "W"
        case UInt32(kVK_ANSI_X): "X"
        case UInt32(kVK_ANSI_Y): "Y"
        case UInt32(kVK_ANSI_Z): "Z"
        case UInt32(kVK_ANSI_0): "0"
        case UInt32(kVK_ANSI_1): "1"
        case UInt32(kVK_ANSI_2): "2"
        case UInt32(kVK_ANSI_3): "3"
        case UInt32(kVK_ANSI_4): "4"
        case UInt32(kVK_ANSI_5): "5"
        case UInt32(kVK_ANSI_6): "6"
        case UInt32(kVK_ANSI_7): "7"
        case UInt32(kVK_ANSI_8): "8"
        case UInt32(kVK_ANSI_9): "9"
        case UInt32(kVK_Space): localized("Space")
        case UInt32(kVK_Return): localized("Return")
        case UInt32(kVK_Tab): localized("Tab")
        case UInt32(kVK_Escape): localized("Escape")
        case UInt32(kVK_F1): "F1"
        case UInt32(kVK_F2): "F2"
        case UInt32(kVK_F3): "F3"
        case UInt32(kVK_F4): "F4"
        case UInt32(kVK_F5): "F5"
        case UInt32(kVK_F6): "F6"
        case UInt32(kVK_F7): "F7"
        case UInt32(kVK_F8): "F8"
        case UInt32(kVK_F9): "F9"
        case UInt32(kVK_F10): "F10"
        case UInt32(kVK_F11): "F11"
        case UInt32(kVK_F12): "F12"
        default: nil
        }
    }

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
        var carbonModifiers: UInt32 = 0

        if flags.contains(.command) {
            carbonModifiers |= UInt32(cmdKey)
        }
        if flags.contains(.option) {
            carbonModifiers |= UInt32(optionKey)
        }
        if flags.contains(.control) {
            carbonModifiers |= UInt32(controlKey)
        }
        if flags.contains(.shift) {
            carbonModifiers |= UInt32(shiftKey)
        }

        return carbonModifiers
    }
}
