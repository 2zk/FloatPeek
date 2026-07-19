import Carbon
import Foundation

@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    private static let shortcutID = EventHotKeyID(
        signature: HotKeyManager.fourCharacterCode("FlPk"),
        id: 1
    )

    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var action: (@MainActor () -> Void)?
    private var registeredShortcut: KeyboardShortcut?

    private init() {}

    @discardableResult
    func registerShortcut(
        _ shortcut: KeyboardShortcut,
        action: @escaping @MainActor () -> Void
    ) -> Bool {
        self.action = action

        guard installEventHandlerIfNeeded() else {
            return false
        }

        if registeredShortcut == shortcut, hotKey != nil {
            return true
        }

        let previousShortcut = registeredShortcut
        unregisterHotKey()

        var hotKeyReference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            Self.shortcutID,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )

        guard status == noErr else {
            NSLog("FloatPeek: failed to register global shortcut %@. status=%d", shortcut.displayName, status)
            if let previousShortcut {
                restoreShortcut(previousShortcut)
            }
            return false
        }

        hotKey = hotKeyReference
        registeredShortcut = shortcut
        return true
    }

    func currentShortcut() -> KeyboardShortcut {
        registeredShortcut ?? KeyboardShortcut.load()
    }

    private func installEventHandlerIfNeeded() -> Bool {
        if eventHandler != nil {
            return true
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var handlerReference: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event,
                      let userData else {
                    return OSStatus(eventNotHandledErr)
                }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr,
                      hotKeyID.signature == HotKeyManager.shortcutID.signature,
                      hotKeyID.id == HotKeyManager.shortcutID.id else {
                    return OSStatus(eventNotHandledErr)
                }

                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    manager.action?()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerReference
        )

        guard status == noErr else {
            NSLog("FloatPeek: failed to install global shortcut handler. status=%d", status)
            return false
        }

        eventHandler = handlerReference
        return true
    }

    private func restoreShortcut(_ shortcut: KeyboardShortcut) {
        var hotKeyReference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            Self.shortcutID,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )

        guard status == noErr else {
            return
        }

        hotKey = hotKeyReference
        registeredShortcut = shortcut
    }

    private func unregisterHotKey() {
        guard let hotKey else {
            registeredShortcut = nil
            return
        }

        UnregisterEventHotKey(hotKey)
        self.hotKey = nil
        registeredShortcut = nil
    }

    nonisolated private static func fourCharacterCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { result, character in
            (result << 8) + OSType(character)
        }
    }

}
