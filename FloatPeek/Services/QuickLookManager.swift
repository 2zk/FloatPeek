import Foundation
@preconcurrency import Quartz

@MainActor
final class QuickLookManager: NSObject,
    @preconcurrency QLPreviewPanelDataSource,
    QLPreviewPanelDelegate {
    static let shared = QuickLookManager()

    private var previewURL: URL?

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
        previewURL = fileURL

        guard let panel = QLPreviewPanel.shared() else {
            return false
        }

        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
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

        previewURL = fileURL
        panel.reloadData()
    }

    func closePreviewIfVisible() {
        previewURL = nil

        guard isPreviewing,
              let panel = QLPreviewPanel.shared() else {
            return
        }

        panel.reloadData()
        panel.orderOut(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewURL as NSURL?
    }
}
