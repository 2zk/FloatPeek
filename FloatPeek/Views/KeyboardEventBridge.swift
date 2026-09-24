@preconcurrency import AppKit
import Carbon
import SwiftUI

struct KeyboardEventBridge: NSViewRepresentable {
    let onKeyDown: (HandledKey) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onKeyDown: onKeyDown)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.installMonitor()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onKeyDown = onKeyDown
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator: @unchecked Sendable {
        var onKeyDown: (HandledKey) -> Bool
        private var monitor: Any?

        init(onKeyDown: @escaping (HandledKey) -> Bool) {
            self.onKeyDown = onKeyDown
        }

        func installMonitor() {
            guard monitor == nil else {
                return
            }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let handledKey = HandledKey(event: event) else {
                    return event
                }

                let didHandle = MainActor.assumeIsolated { [weak self] in
                    NSApp.modalWindow == nil && self?.onKeyDown(handledKey) == true
                }

                return didHandle ? nil : event
            }
        }

        func removeMonitor() {
            guard let monitor else {
                return
            }

            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        deinit {
            removeMonitor()
        }
    }
}

enum HandledKey: Sendable {
    case `return`
    case escape
    case space
    case arrow(ImageSelection.Direction, extendingSelection: Bool)
    case selectAll
    case copy
    case moveToTrash
    case selectNextTab
    case selectPreviousTab

    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let extendingSelection = modifiers.contains(.shift)

        switch Int(event.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter:
            self = .return
        case kVK_Escape:
            self = .escape
        case kVK_Space:
            self = .space
        case kVK_LeftArrow:
            self = .arrow(.left, extendingSelection: extendingSelection)
        case kVK_RightArrow:
            self = .arrow(.right, extendingSelection: extendingSelection)
        case kVK_DownArrow:
            self = .arrow(.down, extendingSelection: extendingSelection)
        case kVK_UpArrow:
            self = .arrow(.up, extendingSelection: extendingSelection)
        case kVK_ANSI_A where modifiers == .command || modifiers == .control:
            self = .selectAll
        case kVK_ANSI_C where modifiers == .command:
            self = .copy
        case kVK_Tab where modifiers == .control:
            self = .selectNextTab
        case kVK_Tab where modifiers == [.control, .shift]:
            self = .selectPreviousTab
        case kVK_Delete, kVK_ForwardDelete:
            guard modifiers.isEmpty, !event.isARepeat else {
                return nil
            }
            self = .moveToTrash
        default:
            return nil
        }
    }
}
