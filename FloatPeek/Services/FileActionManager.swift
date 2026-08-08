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

    func renameFile(_ fileURL: URL, toFileName fileName: String) async throws -> URL
}

enum FileRenameError: Error, Equatable {
    case emptyName
    case invalidName
    case destinationExists
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

    func renameFile(_ fileURL: URL, toFileName fileName: String) async throws -> URL {
        guard !fileName.isEmpty else {
            throw FileRenameError.emptyName
        }
        guard !fileName.contains("/"), fileName != ".", fileName != ".." else {
            throw FileRenameError.invalidName
        }

        let sourceURL = fileURL.standardizedFileURL
        let destinationURL = sourceURL
            .deletingLastPathComponent()
            .appendingPathComponent(fileName, isDirectory: false)
            .standardizedFileURL

        guard sourceURL != destinationURL else {
            return sourceURL
        }

        return try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let isCaseOnlyChange = sourceURL.path.compare(
                destinationURL.path,
                options: [.caseInsensitive, .literal]
            ) == .orderedSame

            if isCaseOnlyChange {
                let temporaryURL = sourceURL
                    .deletingLastPathComponent()
                    .appendingPathComponent(".floatpeek-rename-\(UUID().uuidString)")

                try fileManager.moveItem(at: sourceURL, to: temporaryURL)
                do {
                    try fileManager.moveItem(at: temporaryURL, to: destinationURL)
                } catch {
                    try? fileManager.moveItem(at: temporaryURL, to: sourceURL)
                    throw error
                }
            } else {
                guard !fileManager.fileExists(atPath: destinationURL.path) else {
                    throw FileRenameError.destinationExists
                }
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
            }

            return destinationURL
        }.value
    }
}
