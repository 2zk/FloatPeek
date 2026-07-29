import AppKit
@preconcurrency import Quartz
import XCTest
@testable import FloatPeek

@MainActor
final class QuickLookManagerTests: XCTestCase {
    func testPreviewIdentifiesFloatPeekQuickLookInVisibleTitleBar() throws {
        let fileURL = try makePreviewFile()
        defer { cleanUpPreview(fileURL: fileURL) }

        XCTAssertTrue(QuickLookManager.shared.preview(fileURL: fileURL))

        let panel = try XCTUnwrap(QLPreviewPanel.shared())
        let previewItem = try XCTUnwrap(
            QuickLookManager.shared.previewPanel(panel, previewItemAt: 0)
        )

        XCTAssertEqual(
            previewItem.previewItemTitle,
            "\(localized("FloatPeek Quick Look")) — \(fileURL.lastPathComponent)"
        )
        XCTAssertEqual(panel.titleVisibility, .visible)
        XCTAssertTrue(panel.titlebarAppearsTransparent)
        assertPanelBackgroundColor(panel, equals: .defaultColor)
    }

    func testApplyingBackgroundColorUpdatesVisibleBackground() throws {
        let fileURL = try makePreviewFile()
        defer { cleanUpPreview(fileURL: fileURL) }
        let color = QuickLookBackgroundColor(
            red: 0.1,
            green: 0.2,
            blue: 0.3
        )

        XCTAssertTrue(QuickLookManager.shared.preview(fileURL: fileURL))
        QuickLookManager.shared.applyBackgroundColor(color)

        let panel = try XCTUnwrap(QLPreviewPanel.shared())
        assertPanelBackgroundColor(panel, equals: color)
    }

    func testApplyingBackgroundColorWhileClosedUsesItOnNextPreview() throws {
        let fileURL = try makePreviewFile()
        defer { cleanUpPreview(fileURL: fileURL) }
        let color = QuickLookBackgroundColor(
            red: 0.2,
            green: 0.4,
            blue: 0.6
        )

        QuickLookManager.shared.applyBackgroundColor(color)
        XCTAssertTrue(QuickLookManager.shared.preview(fileURL: fileURL))

        let panel = try XCTUnwrap(QLPreviewPanel.shared())
        assertPanelBackgroundColor(panel, equals: color)
    }

    func testUpdatingPreviewReappliesBackgroundAppearance() throws {
        let firstFileURL = try makePreviewFile()
        let secondFileURL = try makeTemporaryPreviewFile()
        defer {
            cleanUpPreview(fileURL: firstFileURL)
            try? FileManager.default.removeItem(at: secondFileURL)
        }
        let color = QuickLookBackgroundColor(
            red: 0.3,
            green: 0.5,
            blue: 0.7
        )

        XCTAssertTrue(QuickLookManager.shared.preview(fileURL: firstFileURL))
        QuickLookManager.shared.applyBackgroundColor(color)

        let panel = try XCTUnwrap(QLPreviewPanel.shared())
        panel.backgroundColor = .black
        panel.titlebarAppearsTransparent = false

        QuickLookManager.shared.updatePreviewIfVisible(fileURL: secondFileURL)

        XCTAssertTrue(panel.titlebarAppearsTransparent)
        assertPanelBackgroundColor(panel, equals: color)
    }

    func testTogglePreviewClosesVisiblePreview() async throws {
        let fileURL = try makePreviewFile()
        defer { cleanUpPreview(fileURL: fileURL) }

        QuickLookManager.shared.closePreviewIfVisible()
        try await waitForPreviewToClose()

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
        QuickLookManager.shared.applyBackgroundColor(.defaultColor)

        return try makeTemporaryPreviewFile()
    }

    private func makeTemporaryPreviewFile() throws -> URL {
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
        QuickLookManager.shared.applyBackgroundColor(.defaultColor)
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func assertPanelBackgroundColor(
        _ panel: QLPreviewPanel,
        equals expectedColor: QuickLookBackgroundColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let panelColor = panel.backgroundColor.usingColorSpace(.sRGB) else {
            XCTFail("Quick Lookの背景色をsRGBへ変換できない", file: file, line: line)
            return
        }

        XCTAssertEqual(
            panelColor.redComponent,
            expectedColor.red,
            accuracy: 0.001,
            file: file,
            line: line
        )
        XCTAssertEqual(
            panelColor.greenComponent,
            expectedColor.green,
            accuracy: 0.001,
            file: file,
            line: line
        )
        XCTAssertEqual(
            panelColor.blueComponent,
            expectedColor.blue,
            accuracy: 0.001,
            file: file,
            line: line
        )
        XCTAssertEqual(
            panelColor.alphaComponent,
            1,
            accuracy: 0.001,
            file: file,
            line: line
        )
    }
}
