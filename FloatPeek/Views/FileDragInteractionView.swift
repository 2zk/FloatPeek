import AppKit
import SwiftUI

struct FileDragInteractionView: NSViewRepresentable {
    let isSelected: Bool
    let dragURLs: () -> [URL]
    let onSelect: (FileBrowserViewModel.SelectionMode) -> Void
    let onAction: (FileAction) -> Void

    func makeNSView(context: Context) -> FileDragInteractionNSView {
        let view = FileDragInteractionNSView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: FileDragInteractionNSView, context: Context) {
        update(nsView)
    }

    private func update(_ view: FileDragInteractionNSView) {
        view.isSelected = isSelected
        view.dragURLs = dragURLs
        view.onSelect = onSelect
        view.onAction = onAction
    }
}

final class FileDragInteractionNSView: NSView, NSDraggingSource {
    var isSelected = false
    var dragURLs: (() -> [URL])?
    var onSelect: ((FileBrowserViewModel.SelectionMode) -> Void)?
    var onAction: ((FileAction) -> Void)?

    private var didStartDrag = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        didStartDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didStartDrag else {
            return
        }

        didStartDrag = true

        // 未選択の項目は先に単独選択し、選択状態に応じた対象を取得する
        if !isSelected {
            onSelect?(.replace)
        }

        let dragURLs = dragURLs?() ?? []
        guard !dragURLs.isEmpty else {
            return
        }

        beginDraggingSession(
            with: dragURLs.map(makeDraggingItem),
            event: event,
            source: self
        )
    }

    override func mouseUp(with event: NSEvent) {
        guard !didStartDrag else {
            return
        }

        if event.clickCount >= 2 {
            onAction?(.open)
        } else {
            onSelect?(selectionMode(for: event))
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        if !isSelected {
            onSelect?(.replace)
        }

        let menu = NSMenu()
        menu.addItem(makeMenuItem(for: .open))
        menu.addItem(makeMenuItem(for: .preview))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(for: .copy))
        menu.addItem(makeMenuItem(for: .copyPath))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(for: .revealInFinder))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(for: .moveToTrash))
        return menu
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    private func makeDraggingItem(for url: URL) -> NSDraggingItem {
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 64, height: 64)
        let frame = NSRect(
            x: bounds.midX - 32,
            y: bounds.midY - 32,
            width: 64,
            height: 64
        )
        item.setDraggingFrame(frame, contents: icon)
        return item
    }

    private func makeMenuItem(for action: FileAction) -> NSMenuItem {
        let item = NSMenuItem(
            title: Self.menuTitle(for: action),
            action: #selector(performMenuAction(_:)),
            keyEquivalent: action == .copy ? "c" : ""
        )
        if action == .copy {
            item.keyEquivalentModifierMask = .command
        }
        item.target = self
        item.representedObject = action
        return item
    }

    @objc private func performMenuAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? FileAction else {
            return
        }
        onAction?(action)
    }

    private static func menuTitle(for action: FileAction) -> String {
        switch action {
        case .open:
            localized("Open")
        case .preview:
            localized("Quick Look")
        case .copy:
            localized("Copy")
        case .copyPath:
            localized("Copy File Path")
        case .revealInFinder:
            localized("Reveal in Finder")
        case .moveToTrash:
            localized("Move to Trash")
        }
    }

    private func selectionMode(for event: NSEvent) -> FileBrowserViewModel.SelectionMode {
        if event.modifierFlags.contains(.shift) {
            return .range
        }

        if event.modifierFlags.contains(.command) {
            return .toggle
        }

        return .replace
    }
}
