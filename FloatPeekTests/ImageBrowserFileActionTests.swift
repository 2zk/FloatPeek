import AppKit
import XCTest
@testable import FloatPeek

@MainActor
final class ImageBrowserFileActionTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var fileActionManager: TestFileActionManager!
    private var viewModel: ImageBrowserViewModel!

    override func setUp() async throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        try createFile(named: "first.png")
        try createFile(named: "second.png")
        try createFile(named: "third.png")

        fileActionManager = TestFileActionManager()
        viewModel = ImageBrowserViewModel(
            initialFolderURL: temporaryDirectory,
            fileActionManager: fileActionManager
        )
        try await waitForReload()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        viewModel = nil
        fileActionManager = nil
        temporaryDirectory = nil
    }

    func testCopySelectedImagesCopiesAllSelectedFiles() throws {
        let first = try image(named: "first.png")
        let second = try image(named: "second.png")
        viewModel.selectImage(first)
        viewModel.selectImage(second, mode: .toggle)

        XCTAssertTrue(viewModel.copySelectedImages())

        XCTAssertEqual(Set(fileActionManager.copiedFileURLs), Set([first.url, second.url]))
    }

    func testContextActionUsesSelectionWhenTargetIsSelected() throws {
        let first = try image(named: "first.png")
        let second = try image(named: "second.png")
        viewModel.selectImage(first)
        viewModel.selectImage(second, mode: .toggle)

        XCTAssertTrue(viewModel.copyPaths(for: first))
        XCTAssertTrue(viewModel.revealInFinder(first))

        let expectedURLs = Set([first.url, second.url])
        XCTAssertEqual(Set(fileActionManager.copiedPathURLs), expectedURLs)
        XCTAssertEqual(Set(fileActionManager.revealedURLs), expectedURLs)
    }

    func testContextActionUsesOnlyUnselectedTarget() throws {
        let first = try image(named: "first.png")
        let third = try image(named: "third.png")
        viewModel.selectImage(first)

        XCTAssertTrue(viewModel.copyImages(for: third))

        XCTAssertEqual(fileActionManager.copiedFileURLs, [third.url])
    }

    func testCommandCIsHandledAsCopyShortcut() throws {
        let commandC = try XCTUnwrap(makeKeyEvent(modifierFlags: .command))
        let plainC = try XCTUnwrap(makeKeyEvent(modifierFlags: []))

        guard case .copy = HandledKey(event: commandC) else {
            return XCTFail("Command + C がコピー操作として認識されない")
        }
        XCTAssertNil(HandledKey(event: plainC))
    }

    func testContextMenuContainsExpectedActionsAndSelectsUnselectedItem() throws {
        let interactionView = FileDragInteractionNSView()
        var didReplaceSelection = false
        interactionView.onSelect = { mode in
            if case .replace = mode {
                didReplaceSelection = true
            }
        }

        let event = try XCTUnwrap(makeKeyEvent(modifierFlags: []))
        let menu = try XCTUnwrap(interactionView.menu(for: event))

        XCTAssertTrue(didReplaceSelection)
        XCTAssertEqual(
            menu.items.filter { !$0.isSeparatorItem }.map(\.title),
            ["Open", "Quick Look", "Copy", "Copy File Path", "Reveal in Finder"].map(localized)
        )
    }

    func testChangingTabFolderReloadsImagesFromNewFolder() async throws {
        let anotherDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: anotherDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: anotherDirectory)
        }
        try Data("test".utf8).write(
            to: anotherDirectory.appendingPathComponent("another.png")
        )

        viewModel.setFolderURL(anotherDirectory)
        try await waitForReload()

        XCTAssertEqual(viewModel.images.map(\.fileName), ["another.png"])
    }

    private func createFile(named fileName: String) throws {
        try Data("test".utf8).write(
            to: temporaryDirectory.appendingPathComponent(fileName)
        )
    }

    private func image(named fileName: String) throws -> ImageFile {
        try XCTUnwrap(viewModel.images.first { $0.fileName == fileName })
    }

    private func waitForReload() async throws {
        for _ in 0..<100 where viewModel.isReloading {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertFalse(viewModel.isReloading)
    }

    private func makeKeyEvent(modifierFlags: NSEvent.ModifierFlags) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "c",
            charactersIgnoringModifiers: "c",
            isARepeat: false,
            keyCode: 8
        )
    }
}

private final class TestFileActionManager: FileActionHandling {
    private(set) var copiedFileURLs: [URL] = []
    private(set) var copiedPathURLs: [URL] = []
    private(set) var revealedURLs: [URL] = []

    func copyFiles(_ fileURLs: [URL]) -> Bool {
        copiedFileURLs = fileURLs
        return !fileURLs.isEmpty
    }

    func copyPaths(_ fileURLs: [URL]) -> Bool {
        copiedPathURLs = fileURLs
        return !fileURLs.isEmpty
    }

    func revealInFinder(_ fileURLs: [URL]) -> Bool {
        revealedURLs = fileURLs
        return !fileURLs.isEmpty
    }
}
