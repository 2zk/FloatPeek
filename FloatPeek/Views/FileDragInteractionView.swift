import AppKit
import SwiftUI

struct FileDragInteractionView: NSViewRepresentable {
    let imageURL: URL
    let isSelected: Bool
    let selectedDragURLs: [URL]
    let onSelect: (ImageBrowserViewModel.SelectionMode) -> Void
    let onOpen: () -> Void
    let onPreview: () -> Void
    let onCopy: () -> Void
    let onRevealInFinder: () -> Void
    let onCopyPath: () -> Void

    func makeNSView(context: Context) -> FileDragInteractionNSView {
        let view = FileDragInteractionNSView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: FileDragInteractionNSView, context: Context) {
        update(nsView)
    }

    private func update(_ view: FileDragInteractionNSView) {
        view.imageURL = imageURL
        view.isSelected = isSelected
        view.selectedDragURLs = selectedDragURLs
        view.onSelect = onSelect
        view.onOpen = onOpen
        view.onPreview = onPreview
        view.onCopy = onCopy
        view.onRevealInFinder = onRevealInFinder
        view.onCopyPath = onCopyPath
    }
}

final class FileDragInteractionNSView: NSView, NSDraggingSource {
    var imageURL: URL?
    var isSelected = false
    var selectedDragURLs: [URL] = []
    var onSelect: ((ImageBrowserViewModel.SelectionMode) -> Void)?
    var onOpen: (() -> Void)?
    var onPreview: (() -> Void)?
    var onCopy: (() -> Void)?
    var onRevealInFinder: (() -> Void)?
    var onCopyPath: (() -> Void)?

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

        let dragURLs = isSelected ? selectedDragURLs : imageURL.map { [$0] } ?? []
        guard !dragURLs.isEmpty else {
            return
        }

        if !isSelected {
            onSelect?(.replace)
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
            onOpen?()
        } else {
            onSelect?(selectionMode(for: event))
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        if !isSelected {
            onSelect?(.replace)
        }

        let menu = NSMenu()
        menu.addItem(makeMenuItem(title: localized("Open"), action: #selector(openFromMenu)))
        menu.addItem(makeMenuItem(title: localized("Quick Look"), action: #selector(previewFromMenu)))
        menu.addItem(.separator())

        let copyItem = makeMenuItem(title: localized("Copy"), action: #selector(copyFromMenu))
        copyItem.keyEquivalent = "c"
        copyItem.keyEquivalentModifierMask = .command
        menu.addItem(copyItem)

        menu.addItem(makeMenuItem(title: localized("Copy File Path"), action: #selector(copyPathFromMenu)))
        menu.addItem(.separator())
        menu.addItem(
            makeMenuItem(title: localized("Reveal in Finder"), action: #selector(revealInFinderFromMenu))
        )
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

    private func makeMenuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openFromMenu() {
        onOpen?()
    }

    @objc private func previewFromMenu() {
        onPreview?()
    }

    @objc private func copyFromMenu() {
        onCopy?()
    }

    @objc private func copyPathFromMenu() {
        onCopyPath?()
    }

    @objc private func revealInFinderFromMenu() {
        onRevealInFinder?()
    }

    private func selectionMode(for event: NSEvent) -> ImageBrowserViewModel.SelectionMode {
        if event.modifierFlags.contains(.shift) {
            return .range
        }

        if event.modifierFlags.contains(.command) {
            return .toggle
        }

        return .replace
    }
}
