import AppKit
import SwiftUI
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

    func testControlAndCommandAAreHandledAsSelectAllShortcuts() throws {
        for modifiers: NSEvent.ModifierFlags in [.control, .command] {
            let selectAll = try XCTUnwrap(
                makeKeyEvent(modifierFlags: modifiers, keyCode: 0)
            )
            guard case .selectAll = HandledKey(event: selectAll) else {
                return XCTFail("Control または Command + A が全選択として認識されない")
            }
        }
    }

    func testSelectAllImagesSelectsEveryDisplayedFile() throws {
        let focusedImage = try image(named: "second.png")
        viewModel.selectImage(focusedImage)

        XCTAssertTrue(viewModel.selectAllImages())
        XCTAssertEqual(viewModel.selectedImageIDs, Set(viewModel.images.map(\.id)))
        XCTAssertEqual(viewModel.selectedImage?.id, focusedImage.id)
    }

    func testDeleteKeysAreHandledWithoutModifiersOrKeyRepeat() throws {
        for keyCode: UInt16 in [51, 117] {
            let deleteKey = try XCTUnwrap(
                makeKeyEvent(modifierFlags: [], keyCode: keyCode)
            )
            guard case .moveToTrash = HandledKey(event: deleteKey) else {
                return XCTFail("Deleteキーがゴミ箱への移動として認識されない")
            }

            let modifiedDelete = try XCTUnwrap(
                makeKeyEvent(modifierFlags: .command, keyCode: keyCode)
            )
            XCTAssertNil(HandledKey(event: modifiedDelete))

            let repeatedDelete = try XCTUnwrap(
                makeKeyEvent(modifierFlags: [], keyCode: keyCode, isARepeat: true)
            )
            XCTAssertNil(HandledKey(event: repeatedDelete))
        }
    }

    func testArrowKeyReportsWhetherShiftExtendsSelection() throws {
        let shiftedArrow = try XCTUnwrap(
            makeKeyEvent(modifierFlags: .shift, keyCode: 124)
        )
        guard case .rightArrow(let extendingSelection) = HandledKey(event: shiftedArrow) else {
            return XCTFail("Shift + 右矢印が移動操作として認識されない")
        }
        XCTAssertTrue(extendingSelection)

        let plainArrow = try XCTUnwrap(
            makeKeyEvent(modifierFlags: [], keyCode: 124)
        )
        guard case .rightArrow(let extendingSelection) = HandledKey(event: plainArrow) else {
            return XCTFail("右矢印が移動操作として認識されない")
        }
        XCTAssertFalse(extendingSelection)
    }

    func testControlTabShortcutsSelectAdjacentTabs() throws {
        let nextTab = try XCTUnwrap(
            makeKeyEvent(modifierFlags: .control, keyCode: 48)
        )
        guard case .selectNextTab = HandledKey(event: nextTab) else {
            return XCTFail("Control + Tab が次のフォルダへの切り替えとして認識されない")
        }

        let previousTab = try XCTUnwrap(
            makeKeyEvent(modifierFlags: [.control, .shift], keyCode: 48)
        )
        guard case .selectPreviousTab = HandledKey(event: previousTab) else {
            return XCTFail("Control + Shift + Tab が前のフォルダへの切り替えとして認識されない")
        }
    }

    func testTabWithOtherModifiersIsNotHandledAsFolderShortcut() throws {
        let commandTab = try XCTUnwrap(
            makeKeyEvent(modifierFlags: .command, keyCode: 48)
        )
        let controlOptionTab = try XCTUnwrap(
            makeKeyEvent(modifierFlags: [.control, .option], keyCode: 48)
        )

        XCTAssertNil(HandledKey(event: commandTab))
        XCTAssertNil(HandledKey(event: controlOptionTab))
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
            [
                "Open",
                "Quick Look",
                "Copy",
                "Copy File Path",
                "Reveal in Finder",
                "Move to Trash",
            ].map(localized)
        )
    }

    func testMoveSelectedImagesToTrashMovesAllSelectedImagesAndSelectsNext() async throws {
        viewModel.setSortOption(.fileName)
        let first = try image(named: "first.png")
        let second = try image(named: "second.png")
        let third = try image(named: "third.png")
        viewModel.selectImage(first)
        viewModel.selectImage(second, mode: .toggle)

        XCTAssertTrue(viewModel.moveSelectedImagesToTrash())
        try await waitForTrashOperation()

        XCTAssertEqual(fileActionManager.movedToTrashURLs, [first.url, second.url])
        XCTAssertEqual(viewModel.images.map(\.fileName), ["third.png"])
        XCTAssertEqual(viewModel.selectedImage?.id, third.id)
        XCTAssertEqual(viewModel.selectedImageIDs, [third.id])
    }

    func testMoveSelectedContextImageMovesAllSelectedImages() async throws {
        viewModel.setSortOption(.fileName)
        let first = try image(named: "first.png")
        let second = try image(named: "second.png")
        let third = try image(named: "third.png")
        viewModel.selectImage(first)
        viewModel.selectImage(second, mode: .toggle)

        XCTAssertTrue(viewModel.moveImagesToTrash(for: first))
        try await waitForTrashOperation()

        XCTAssertEqual(fileActionManager.movedToTrashURLs, [first.url, second.url])
        XCTAssertEqual(viewModel.selectedImage?.id, third.id)
        XCTAssertEqual(viewModel.selectedImageIDs, [third.id])
    }

    func testMoveUnselectedContextImageMovesOnlyTargetImage() async throws {
        viewModel.setSortOption(.fileName)
        let first = try image(named: "first.png")
        let third = try image(named: "third.png")
        viewModel.selectImage(first)

        XCTAssertTrue(viewModel.moveImagesToTrash(for: third))
        try await waitForTrashOperation()

        XCTAssertEqual(fileActionManager.movedToTrashURLs, [third.url])
        XCTAssertEqual(viewModel.selectedImage?.id, first.id)
        XCTAssertEqual(viewModel.selectedImageIDs, [first.id])
    }

    func testMovingLastThenOnlyRemainingImagesUpdatesSelection() async throws {
        viewModel.setSortOption(.fileName)
        let third = try image(named: "third.png")
        viewModel.selectImage(third)

        XCTAssertTrue(viewModel.moveSelectedImagesToTrash())
        try await waitForTrashOperation()
        XCTAssertEqual(viewModel.selectedImage?.fileName, "second.png")

        XCTAssertTrue(viewModel.moveSelectedImagesToTrash())
        try await waitForTrashOperation()
        XCTAssertEqual(viewModel.selectedImage?.fileName, "first.png")

        XCTAssertTrue(viewModel.moveSelectedImagesToTrash())
        try await waitForTrashOperation()
        XCTAssertNil(viewModel.selectedImage)
        XCTAssertEqual(viewModel.displayState, .noImages)
    }

    func testMoveToTrashFailurePreservesImagesAndSelection() async throws {
        let first = try image(named: "first.png")
        let second = try image(named: "second.png")
        viewModel.selectImage(first)
        viewModel.selectImage(second, mode: .toggle)
        fileActionManager.moveToTrashError = NSError(
            domain: "FloatPeekTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Test failure"]
        )

        XCTAssertTrue(viewModel.moveSelectedImagesToTrash())
        try await waitForTrashOperation()

        XCTAssertEqual(viewModel.images.count, 3)
        XCTAssertEqual(viewModel.selectedImageIDs, [first.id, second.id])
        XCTAssertTrue(viewModel.fileActionErrorMessage?.contains("2") == true)
    }

    func testSingleSelectedImageCanBeRenamed() async throws {
        viewModel.setSortOption(.fileName)
        let first = try image(named: "first.png")
        viewModel.selectImage(first)

        XCTAssertEqual(viewModel.selectedImageForRenaming?.id, first.id)
        let didRename = await viewModel.renameImage(first, toBaseName: "renamed")
        XCTAssertTrue(didRename)
        try await waitForReload()

        let renamedURL = temporaryDirectory.appendingPathComponent("renamed.png")
        let resolvedRenamedURL = renamedURL.resolvingSymlinksInPath()
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.url.path))
        XCTAssertEqual(viewModel.selectedImage?.id.resolvingSymlinksInPath(), resolvedRenamedURL)
        XCTAssertEqual(
            Set(viewModel.selectedImageIDs.map { $0.resolvingSymlinksInPath() }),
            [resolvedRenamedURL]
        )
        XCTAssertEqual(
            viewModel.images.map(\.fileName),
            ["renamed.png", "second.png", "third.png"]
        )
    }

    func testRenameResortsFilesByName() async throws {
        viewModel.setSortOption(.fileName)
        let first = try image(named: "first.png")
        viewModel.selectImage(first)

        let didRename = await viewModel.renameImage(first, toBaseName: "z-last")
        XCTAssertTrue(didRename)
        try await waitForReload()

        XCTAssertEqual(
            viewModel.images.map(\.fileName),
            ["second.png", "third.png", "z-last.png"]
        )
        XCTAssertEqual(viewModel.selectedImage?.fileName, "z-last.png")
    }

    func testMultipleSelectedImagesCannotEnterRenameMode() throws {
        let first = try image(named: "first.png")
        let second = try image(named: "second.png")
        viewModel.selectImage(first)
        viewModel.selectImage(second, mode: .toggle)

        XCTAssertNil(viewModel.selectedImageForRenaming)
    }

    func testRenameFailurePreservesFileAndSelection() async throws {
        let first = try image(named: "first.png")
        viewModel.selectImage(first)
        fileActionManager.renameError = NSError(
            domain: "FloatPeekTests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Rename failure"]
        )

        let didRename = await viewModel.renameImage(first, toBaseName: "renamed")
        XCTAssertFalse(didRename)

        XCTAssertTrue(FileManager.default.fileExists(atPath: first.url.path))
        XCTAssertEqual(viewModel.selectedImage?.id, first.id)
        XCTAssertEqual(viewModel.fileActionErrorTitle, localized("Could not Rename File"))
        XCTAssertTrue(viewModel.fileActionErrorMessage?.contains("Rename failure") == true)
    }

    func testFileActionManagerRejectsInvalidRenameNamesAndCollisions() async throws {
        let first = temporaryDirectory.appendingPathComponent("first.png")
        let manager = FileActionManager()

        for invalidName in ["", ".", "..", "nested/name.png"] {
            do {
                _ = try await manager.renameFile(first, toFileName: invalidName)
                XCTFail("不正なファイル名が受け入れられた: \(invalidName)")
            } catch {
                XCTAssertTrue(error is FileRenameError)
            }
        }

        do {
            _ = try await manager.renameFile(first, toFileName: "second.png")
            XCTFail("既存ファイルと同名への変更が受け入れられた")
        } catch {
            XCTAssertEqual(error as? FileRenameError, .destinationExists)
        }
    }

    func testFileActionManagerSupportsCaseOnlyRename() async throws {
        let first = temporaryDirectory.appendingPathComponent("first.png")
        let renamedURL = try await FileActionManager().renameFile(
            first,
            toFileName: "FIRST.png"
        )

        XCTAssertEqual(renamedURL.lastPathComponent, "FIRST.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedURL.path))
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

    private func waitForTrashOperation() async throws {
        for _ in 0..<100 where viewModel.isMovingToTrash || viewModel.isReloading {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertFalse(viewModel.isMovingToTrash)
        XCTAssertFalse(viewModel.isReloading)
    }

    private func makeKeyEvent(
        modifierFlags: NSEvent.ModifierFlags,
        keyCode: UInt16 = 8,
        isARepeat: Bool = false
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "c",
            charactersIgnoringModifiers: "c",
            isARepeat: isARepeat,
            keyCode: keyCode
        )
    }
}

private final class TestFileActionManager: FileActionHandling {
    private(set) var copiedFileURLs: [URL] = []
    private(set) var copiedPathURLs: [URL] = []
    private(set) var revealedURLs: [URL] = []
    private(set) var movedToTrashURLs: [URL] = []
    private(set) var renamedFiles: [(source: URL, fileName: String)] = []
    var moveToTrashError: Error?
    var renameError: Error?

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

    func moveToTrash(_ fileURLs: [URL]) async throws {
        if let moveToTrashError {
            throw moveToTrashError
        }

        movedToTrashURLs.append(contentsOf: fileURLs)
        for fileURL in fileURLs {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    func renameFile(_ fileURL: URL, toFileName fileName: String) async throws -> URL {
        if let renameError {
            throw renameError
        }

        renamedFiles.append((fileURL, fileName))
        let destinationURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent(fileName)
        try FileManager.default.moveItem(at: fileURL, to: destinationURL)
        return destinationURL
    }
}

@MainActor
final class ImageFileTileFocusTests: XCTestCase {
    func testEnteringRenameModeFocusesFieldAndAcceptsTypingWithoutClick() async throws {
        let model = RenameTileTestModel()
        let hostingView = NSHostingView(rootView: RenameTileTestView(model: model))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 180),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.close()
        }

        model.isRenaming = true

        let originalName = model.image.url.deletingPathExtension().lastPathComponent
        let didFocusRenameField = await waitUntil {
            guard let fieldEditor = window.firstResponder as? NSTextView else {
                return false
            }

            return fieldEditor.isFieldEditor
                && fieldEditor.string == originalName
                && fieldEditor.selectedRange() == NSRange(
                    location: 0,
                    length: originalName.utf16.count
                )
        }
        XCTAssertTrue(didFocusRenameField)

        let typedCharacter = "x"
        let typingEvent = try XCTUnwrap(
            makeKeyEvent(
                characters: typedCharacter,
                keyCode: 7,
                windowNumber: window.windowNumber
            )
        )
        window.sendEvent(typingEvent)

        let didAcceptTyping = await waitUntil {
            (window.firstResponder as? NSTextView)?.string == typedCharacter
        }
        XCTAssertTrue(didAcceptTyping)

        let returnEvent = try XCTUnwrap(
            makeKeyEvent(
                characters: "\r",
                keyCode: 36,
                windowNumber: window.windowNumber
            )
        )
        window.sendEvent(returnEvent)

        let didSubmitRename = await waitUntil {
            model.renamedBaseName == typedCharacter
        }
        XCTAssertTrue(didSubmitRename)
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            if condition() {
                return true
            }
            await Task.yield()
        }

        return condition()
    }

    private func makeKeyEvent(
        characters: String,
        keyCode: UInt16,
        windowNumber: Int
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )
    }
}

@MainActor
private final class RenameTileTestModel: ObservableObject {
    @Published var isRenaming = false
    @Published var renamedBaseName: String?

    let image = ImageFile(
        url: URL(fileURLWithPath: "/tmp/original.txt"),
        addedAt: nil,
        modifiedAt: nil
    )
}

private struct RenameTileTestView: View {
    @ObservedObject var model: RenameTileTestModel

    var body: some View {
        ImageFileTile(
            image: model.image,
            isSelected: true,
            isRenaming: model.isRenaming,
            selectedDragURLs: [],
            thumbnailHeight: 100,
            thumbnailSize: CGSize(width: 64, height: 64),
            onSelect: { _ in },
            onOpen: {},
            onPreview: {},
            onCopy: {},
            onRevealInFinder: {},
            onCopyPath: {},
            onMoveToTrash: {},
            onRename: { model.renamedBaseName = $0 },
            onCancelRename: {}
        )
        .frame(width: 160, height: 160)
    }
}
