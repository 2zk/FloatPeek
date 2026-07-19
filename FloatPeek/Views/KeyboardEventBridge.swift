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
    case leftArrow
    case rightArrow
    case upArrow
    case downArrow
    case copy

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
            self = .leftArrow
        case 124:
            self = .rightArrow
        case 125:
            self = .downArrow
        case 126:
            self = .upArrow
        case 8 where modifiers == .command:
            self = .copy
        default:
            return nil
        }
    }
}
