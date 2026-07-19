import AppKit
import Foundation

@MainActor
protocol FileOpening {
    @discardableResult
    func open(_ fileURL: URL) -> Bool
}

struct FileOpener: FileOpening {
    func open(_ fileURL: URL) -> Bool {
        NSWorkspace.shared.open(fileURL)
    }
}
