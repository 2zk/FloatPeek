import XCTest
@testable import FloatPeek

final class FolderMonitorTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var monitor: FolderMonitor!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        monitor = FolderMonitor(debounceInterval: 0.1, eventLatency: 0.05)
    }

    override func tearDown() async throws {
        await monitor.stopMonitoring()
        monitor = nil
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testSupportedFileChangeIsDebouncedIntoSingleNotification() async throws {
        let changeExpectation = expectation(description: "フォルダ変更通知")
        changeExpectation.assertForOverFulfill = true
        await startMonitoring(folderURL: temporaryDirectory) {
            changeExpectation.fulfill()
        }

        try createFile(named: "first.png")
        try createFile(named: "second.jpg")
        try createFile(named: "third.pdf")

        await fulfillment(of: [changeExpectation], timeout: 3)
    }

    func testOverwritingSupportedFileSendsChange() async throws {
        try createFile(named: "image.png")
        let changeExpectation = expectation(description: "上書き変更通知")
        await startMonitoring(folderURL: temporaryDirectory) {
            changeExpectation.fulfill()
        }

        try Data("updated".utf8).write(
            to: temporaryDirectory.appendingPathComponent("image.png")
        )

        await fulfillment(of: [changeExpectation], timeout: 3)
    }

    func testContinuousChangesDoNotPostponeNotificationIndefinitely() async throws {
        try createFile(named: "image.png")
        monitor = FolderMonitor(debounceInterval: 0.2, eventLatency: 0.01)
        let changeExpectation = expectation(description: "連続変更中の通知")
        await startMonitoring(folderURL: temporaryDirectory) {
            changeExpectation.fulfill()
        }

        let fileURL = temporaryDirectory.appendingPathComponent("image.png")
        let writer = Task.detached {
            for index in 0..<20 {
                try Data("updated-\(index)".utf8).write(to: fileURL)
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }

        await fulfillment(of: [changeExpectation], timeout: 0.7)
        await monitor.stopMonitoring()
        _ = try await writer.value
    }

    func testRenamingSupportedFileSendsChange() async throws {
        try createFile(named: "before.png")
        let changeExpectation = expectation(description: "名前変更通知")
        await startMonitoring(folderURL: temporaryDirectory) {
            changeExpectation.fulfill()
        }

        try FileManager.default.moveItem(
            at: temporaryDirectory.appendingPathComponent("before.png"),
            to: temporaryDirectory.appendingPathComponent("after.png")
        )

        await fulfillment(of: [changeExpectation], timeout: 3)
    }

    func testDeletingSupportedFileSendsChange() async throws {
        try createFile(named: "image.png")
        let changeExpectation = expectation(description: "削除変更通知")
        await startMonitoring(folderURL: temporaryDirectory) {
            changeExpectation.fulfill()
        }

        try FileManager.default.removeItem(
            at: temporaryDirectory.appendingPathComponent("image.png")
        )

        await fulfillment(of: [changeExpectation], timeout: 3)
    }

    func testUnsupportedHiddenAndNestedFileChangesAreIgnored() async throws {
        let changeExpectation = expectation(description: "無視対象の変更通知なし")
        changeExpectation.isInverted = true
        let nestedDirectory = temporaryDirectory
            .appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(
            at: nestedDirectory,
            withIntermediateDirectories: true
        )
        await startMonitoring(folderURL: temporaryDirectory) {
            changeExpectation.fulfill()
        }

        try createFile(named: "notes.unsupported")
        try createFile(named: ".hidden.png")
        try Data("test".utf8).write(
            to: nestedDirectory.appendingPathComponent("nested.png")
        )

        await fulfillment(of: [changeExpectation], timeout: 0.8)
    }

    func testDeselectedFileExtensionChangeIsIgnored() async throws {
        let changeExpectation = expectation(description: "選択されていない拡張子の変更通知なし")
        changeExpectation.isInverted = true
        await startMonitoring(
            folderURL: temporaryDirectory,
            displayedFileExtensions: ["png"]
        ) {
            changeExpectation.fulfill()
        }

        try createFile(named: "image.jpg")

        await fulfillment(of: [changeExpectation], timeout: 0.8)
    }

    func testSelectedDocumentExtensionSendsChange() async throws {
        let changeExpectation = expectation(description: "文書ファイルの変更通知")
        await startMonitoring(
            folderURL: temporaryDirectory,
            displayedFileExtensions: ["docx"]
        ) {
            changeExpectation.fulfill()
        }

        try createFile(named: "report.DOCX")

        await fulfillment(of: [changeExpectation], timeout: 3)
    }

    func testStopMonitoringSuppressesChanges() async throws {
        let changeExpectation = expectation(description: "監視停止後の変更通知なし")
        changeExpectation.isInverted = true
        await startMonitoring(folderURL: temporaryDirectory) {
            changeExpectation.fulfill()
        }

        await monitor.stopMonitoring()
        try createFile(named: "stopped.png")

        await fulfillment(of: [changeExpectation], timeout: 0.8)
    }

    func testChangingFolderStopsMonitoringPreviousFolder() async throws {
        let oldFolderExpectation = expectation(description: "旧フォルダの変更通知なし")
        oldFolderExpectation.isInverted = true
        let newFolderExpectation = expectation(description: "新フォルダの変更通知")
        let newDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: newDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: newDirectory)
        }

        await startMonitoring(folderURL: temporaryDirectory) {
            oldFolderExpectation.fulfill()
        }
        await startMonitoring(folderURL: newDirectory) {
            newFolderExpectation.fulfill()
        }

        try createFile(named: "old.png")
        try Data("test".utf8).write(to: newDirectory.appendingPathComponent("new.png"))

        await fulfillment(of: [newFolderExpectation, oldFolderExpectation], timeout: 3)
    }

    func testRemovingMonitoredFolderSendsChange() async throws {
        let changeExpectation = expectation(description: "監視フォルダ削除通知")
        await startMonitoring(folderURL: temporaryDirectory) {
            changeExpectation.fulfill()
        }

        try FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil

        await fulfillment(of: [changeExpectation], timeout: 3)
    }

    private func createFile(named fileName: String) throws {
        try Data("test".utf8).write(
            to: temporaryDirectory.appendingPathComponent(fileName)
        )
    }

    private func startMonitoring(
        folderURL: URL,
        displayedFileExtensions: Set<String> = ImageFileLoader.supportedExtensions,
        onChange: @escaping @Sendable () -> Void
    ) async {
        let didStartMonitoring = await monitor.startMonitoring(
            folderURL: folderURL,
            displayedFileExtensions: displayedFileExtensions,
            onChange: onChange
        )
        XCTAssertTrue(didStartMonitoring)
    }
}

@MainActor
final class ImageBrowserMonitoringTests: XCTestCase {
    func testMonitorChangeReloadsImages() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let monitor = TestFolderMonitor()
        let viewModel = ImageBrowserViewModel(
            initialFolderURL: temporaryDirectory,
            folderMonitor: monitor
        )
        viewModel.startMonitoring()
        try Data("test".utf8).write(
            to: temporaryDirectory.appendingPathComponent("new.png")
        )

        monitor.sendChange()
        for _ in 0..<100 where viewModel.isReloading || viewModel.images.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertFalse(viewModel.isReloading)
        XCTAssertEqual(viewModel.images.map(\.fileName), ["new.png"])
    }
}

private final class TestFolderMonitor: FolderMonitoring, @unchecked Sendable {
    private var onChange: (@Sendable () -> Void)?

    func startMonitoring(
        folderURL: URL,
        displayedFileExtensions: Set<String>,
        onChange: @escaping @Sendable () -> Void
    ) async -> Bool {
        self.onChange = onChange
        return true
    }

    func stopMonitoring() async {
        onChange = nil
    }

    func sendChange() {
        onChange?()
    }
}
