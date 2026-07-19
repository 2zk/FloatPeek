import AppKit
import XCTest
@testable import FloatPeek

@MainActor
final class QuickLookManagerTests: XCTestCase {
    func testTogglePreviewClosesVisiblePreview() async throws {
        let fileURL = try makePreviewFile()
        defer { cleanUpPreview(fileURL: fileURL) }

        QuickLookManager.shared.closePreviewIfVisible()

        XCTAssertTrue(QuickLookManager.shared.togglePreview(fileURL: fileURL))
        XCTAssertTrue(QuickLookManager.shared.isPreviewing)
        XCTAssertTrue(QuickLookManager.shared.togglePreview(fileURL: fileURL))

        try await waitForPreviewToClose()

        XCTAssertFalse(QuickLookManager.shared.isPreviewing)
    }

    func testWindowBecomingHiddenClosesVisiblePreview() async throws {
        let fileURL = try makePreviewFile()
        defer { cleanUpPreview(fileURL: fileURL) }

        XCTAssertTrue(QuickLookManager.shared.preview(fileURL: fileURL))

        WindowManager.shared.windowDidMiniaturize(
            Notification(name: NSWindow.didMiniaturizeNotification)
        )
        try await waitForPreviewToClose()

        XCTAssertFalse(QuickLookManager.shared.isPreviewing)
    }

    func testApplicationHidingClosesVisiblePreview() async throws {
        let fileURL = try makePreviewFile()
        defer { cleanUpPreview(fileURL: fileURL) }

        XCTAssertTrue(QuickLookManager.shared.preview(fileURL: fileURL))

        AppDelegate().applicationWillHide(
            Notification(name: NSApplication.willHideNotification)
        )
        try await waitForPreviewToClose()

        XCTAssertFalse(QuickLookManager.shared.isPreviewing)
    }

    private func makePreviewFile() throws -> URL {
        QuickLookManager.shared.closePreviewIfVisible()

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        try Data("preview".utf8).write(to: fileURL)
        return fileURL
    }

    private func waitForPreviewToClose() async throws {
        for _ in 0..<100 where QuickLookManager.shared.isPreviewing {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func cleanUpPreview(fileURL: URL) {
        QuickLookManager.shared.closePreviewIfVisible()
        try? FileManager.default.removeItem(at: fileURL)
    }
}
