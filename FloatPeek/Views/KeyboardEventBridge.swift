@preconcurrency import AppKit
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
    case leftArrow(extendingSelection: Bool)
    case rightArrow(extendingSelection: Bool)
    case upArrow(extendingSelection: Bool)
    case downArrow(extendingSelection: Bool)
    case copy
    case moveToTrash
    case selectNextTab
    case selectPreviousTab

    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])

        switch event.keyCode {
        case 36, 76:
            self = .return
        case 53:
            self = .escape
        case 49:
            self = .space
        case 123:
            self = .leftArrow(extendingSelection: modifiers.contains(.shift))
        case 124:
            self = .rightArrow(extendingSelection: modifiers.contains(.shift))
        case 125:
            self = .downArrow(extendingSelection: modifiers.contains(.shift))
        case 126:
            self = .upArrow(extendingSelection: modifiers.contains(.shift))
        case 8 where modifiers == .command:
            self = .copy
        case 48 where modifiers == .control:
            self = .selectNextTab
        case 48 where modifiers == [.control, .shift]:
            self = .selectPreviousTab
        case 51, 117:
            guard modifiers.isEmpty, !event.isARepeat else {
                return nil
            }
            self = .moveToTrash
        default:
            return nil
        }
    }
}
