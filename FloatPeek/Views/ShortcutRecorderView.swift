import AppKit
import SwiftUI

struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var shortcut: KeyboardShortcut

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.onShortcutChange = { shortcut in
            self.shortcut = shortcut
        }
        view.displayText = shortcut.displayName
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.displayText = shortcut.displayName
    }
}

final class ShortcutRecorderNSView: NSView {
    var onShortcutChange: ((KeyboardShortcut) -> Void)?
    var displayText = "" {
        didSet {
            needsDisplay = true
        }
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        captureShortcut(from: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        captureShortcut(from: event)
        return true
    }

    private func captureShortcut(from event: NSEvent) {
        guard let shortcut = KeyboardShortcut(event: event),
              shortcut.isValid else {
            NSSound.beep()
            return
        }

        onShortcutChange?(shortcut)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let borderColor = window?.firstResponder === self ? NSColor.controlAccentColor : NSColor.separatorColor
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        borderColor.setStroke()
        path.lineWidth = 2
        path.stroke()

        let text = displayText.isEmpty ? localized("Click and type shortcut") : displayText
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedText.size()
        let textRect = NSRect(
            x: bounds.midX - textSize.width / 2,
            y: bounds.midY - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        attributedText.draw(in: textRect)
    }
}
