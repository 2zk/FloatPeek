import AppKit
import Foundation

@MainActor
protocol FileActionHandling {
    @discardableResult
    func copyFiles(_ fileURLs: [URL]) -> Bool

    @discardableResult
    func copyPaths(_ fileURLs: [URL]) -> Bool

    @discardableResult
    func revealInFinder(_ fileURLs: [URL]) -> Bool

    func moveToTrash(_ fileURLs: [URL]) async throws
}

struct FileActionManager: FileActionHandling {
    func copyFiles(_ fileURLs: [URL]) -> Bool {
        guard !fileURLs.isEmpty else {
            return false
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects(fileURLs.map { $0 as NSURL })
    }

    func copyPaths(_ fileURLs: [URL]) -> Bool {
        guard !fileURLs.isEmpty else {
            return false
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(
            fileURLs.map(\.path).joined(separator: "\n"),
            forType: .string
        )
    }

    func revealInFinder(_ fileURLs: [URL]) -> Bool {
        guard !fileURLs.isEmpty else {
            return false
        }

        NSWorkspace.shared.activateFileViewerSelecting(fileURLs)
        return true
    }

    func moveToTrash(_ fileURLs: [URL]) async throws {
        guard !fileURLs.isEmpty else {
            return
        }

        _ = try await NSWorkspace.shared.recycle(fileURLs)
    }
}
