import Foundation
@preconcurrency import Quartz

@MainActor
final class QuickLookManager: NSObject,
    @preconcurrency QLPreviewPanelDataSource,
    QLPreviewPanelDelegate {
    static let shared = QuickLookManager()

    private final class PreviewItem: NSObject, QLPreviewItem {
        let previewItemURL: URL?
        let previewItemTitle: String?

        init(fileURL: URL, title: String) {
            previewItemURL = fileURL
            previewItemTitle = title
        }
    }

    private var previewItem: PreviewItem?
    private var backgroundColor = AppSettings.loadQuickLookBackgroundColor()

    private override init() {}

    var isPreviewing: Bool {
        guard QLPreviewPanel.sharedPreviewPanelExists(),
              let panel = QLPreviewPanel.shared() else {
            return false
        }

        return panel.isVisible
    }

    @discardableResult
    func preview(fileURL: URL) -> Bool {
        previewItem = makePreviewItem(fileURL: fileURL)

        guard let panel = QLPreviewPanel.shared() else {
            return false
        }

        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        configureAppearance(of: panel)
        panel.makeKeyAndOrderFront(nil)
        return true
    }

    @discardableResult
    func togglePreview(fileURL: URL) -> Bool {
        if isPreviewing {
            closePreviewIfVisible()
            return true
        }

        return preview(fileURL: fileURL)
    }

    func updatePreviewIfVisible(fileURL: URL) {
        guard isPreviewing,
              let panel = QLPreviewPanel.shared() else {
            return
        }

        previewItem = makePreviewItem(fileURL: fileURL)
        panel.reloadData()
        configureAppearance(of: panel)
    }

    func closePreviewIfVisible() {
        previewItem = nil

        guard isPreviewing,
              let panel = QLPreviewPanel.shared() else {
            return
        }

        panel.reloadData()
        panel.orderOut(nil)
    }

    func applyBackgroundColor(_ color: QuickLookBackgroundColor) {
        backgroundColor = color.normalized()

        guard isPreviewing,
              let panel = QLPreviewPanel.shared() else {
            return
        }

        panel.backgroundColor = makeBackgroundColor()
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewItem == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewItem
    }

    private func configureAppearance(of panel: QLPreviewPanel) {
        panel.titleVisibility = .visible
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = makeBackgroundColor()
    }

    private func makeBackgroundColor() -> NSColor {
        NSColor(
            srgbRed: backgroundColor.red,
            green: backgroundColor.green,
            blue: backgroundColor.blue,
            alpha: 1
        )
    }

    private func makePreviewItem(fileURL: URL) -> PreviewItem {
        PreviewItem(
            fileURL: fileURL,
            title: "\(localized("FloatPeek Quick Look")) — \(fileURL.lastPathComponent)"
        )
    }
}
