import AppKit
import XCTest
@testable import FloatPeek

@MainActor
final class FileBrowserActionTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var fileActionManager: TestFileActionManager!
    private var filePreviewer: TestFilePreviewer!
    private var viewModel: FileBrowserViewModel!

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
        filePreviewer = TestFilePreviewer()
        viewModel = FileBrowserViewModel(
            initialFolderURL: temporaryDirectory,
            fileActionManager: fileActionManager,
            filePreviewer: filePreviewer
        )
        try await waitForReload()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        viewModel = nil
        filePreviewer = nil
        fileActionManager = nil
        temporaryDirectory = nil
    }

    func testCopySelectedFilesCopiesAllSelectedFiles() throws {
        let first = try file(named: "first.png")
        let second = try file(named: "second.png")
        viewModel.selectFile(first)
        viewModel.selectFile(second, mode: .toggle)

        XCTAssertTrue(viewModel.copySelectedFiles())

        XCTAssertEqual(Set(fileActionManager.copiedFileURLs), Set([first.url, second.url]))
    }

    func testContextActionUsesSelectionWhenTargetIsSelected() throws {
        let first = try file(named: "first.png")
        let second = try file(named: "second.png")
        viewModel.selectFile(first)
        viewModel.selectFile(second, mode: .toggle)

        XCTAssertTrue(viewModel.copyPaths(for: first))
        XCTAssertTrue(viewModel.revealInFinder(first))

        let expectedURLs = Set([first.url, second.url])
        XCTAssertEqual(Set(fileActionManager.copiedPathURLs), expectedURLs)
        XCTAssertEqual(Set(fileActionManager.revealedURLs), expectedURLs)
    }

    func testContextActionUsesOnlyUnselectedTarget() throws {
        let first = try file(named: "first.png")
        let third = try file(named: "third.png")
        viewModel.selectFile(first)

        XCTAssertTrue(viewModel.copyFiles(for: third))

        XCTAssertEqual(fileActionManager.copiedFileURLs, [third.url])
    }

    func testActionURLsUseSelectionOnlyWhenTargetIsSelected() throws {
        let first = try file(named: "first.png")
        let second = try file(named: "second.png")
        let third = try file(named: "third.png")
        viewModel.selectFile(first)
        viewModel.selectFile(second, mode: .toggle)

        XCTAssertEqual(Set(viewModel.actionURLs(for: first)), [first.url, second.url])
        XCTAssertEqual(viewModel.actionURLs(for: third), [third.url])
    }

    func testPerformFileActionDispatchesToFileActionManager() throws {
        let first = try file(named: "first.png")
        let second = try file(named: "second.png")
        viewModel.selectFile(first)
        viewModel.selectFile(second, mode: .toggle)

        viewModel.performFileAction(.copy, for: first)
        viewModel.performFileAction(.copyPath, for: first)
        viewModel.performFileAction(.revealInFinder, for: first)

        let expectedURLs: Set<URL> = [first.url, second.url]
        XCTAssertEqual(Set(fileActionManager.copiedFileURLs), expectedURLs)
        XCTAssertEqual(Set(fileActionManager.copiedPathURLs), expectedURLs)
        XCTAssertEqual(Set(fileActionManager.revealedURLs), expectedURLs)
    }

    func testPreviewActionSelectsUnselectedFileAndShowsPreview() throws {
        let first = try file(named: "first.png")
        let third = try file(named: "third.png")
        viewModel.selectFile(first)

        viewModel.performFileAction(.preview, for: third)

        XCTAssertEqual(viewModel.selectedFileIDs, [third.id])
        XCTAssertEqual(filePreviewer.previewedURLs, [third.url])
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

    func testSelectAllFilesSelectsEveryDisplayedFile() throws {
        let focusedFile = try file(named: "second.png")
        viewModel.selectFile(focusedFile)

        XCTAssertTrue(viewModel.selectAllFiles())
        XCTAssertEqual(viewModel.selectedFileIDs, Set(viewModel.files.map(\.id)))
        XCTAssertEqual(viewModel.selectedFile?.id, focusedFile.id)
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
        guard case .arrow(.right, let extendingSelection) = HandledKey(event: shiftedArrow) else {
            return XCTFail("Shift + 右矢印が移動操作として認識されない")
        }
        XCTAssertTrue(extendingSelection)

        let plainArrow = try XCTUnwrap(
            makeKeyEvent(modifierFlags: [], keyCode: 124)
        )
        guard case .arrow(.right, let extendingSelection) = HandledKey(event: plainArrow) else {
            return XCTFail("右矢印が移動操作として認識されない")
        }
        XCTAssertFalse(extendingSelection)
    }

    func testArrowKeysMapToSelectionDirections() throws {
        let expectedDirections: [(UInt16, FileSelection.Direction)] = [
            (123, .left),
            (124, .right),
            (125, .down),
            (126, .up)
        ]

        for (keyCode, expectedDirection) in expectedDirections {
            let event = try XCTUnwrap(makeKeyEvent(modifierFlags: [], keyCode: keyCode))
            guard case .arrow(let direction, _) = HandledKey(event: event) else {
                return XCTFail("キーコード \(keyCode) が矢印キーとして認識されない")
            }
            XCTAssertEqual(direction, expectedDirection)
        }
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

    func testContextMenuItemsPerformCorrespondingFileActions() throws {
        let interactionView = FileDragInteractionNSView()
        interactionView.isSelected = true
        var performedActions: [FileAction] = []
        interactionView.onAction = { performedActions.append($0) }

        let event = try XCTUnwrap(makeKeyEvent(modifierFlags: []))
        let menu = try XCTUnwrap(interactionView.menu(for: event))
        for item in menu.items where !item.isSeparatorItem {
            let action = try XCTUnwrap(item.action)
            XCTAssertTrue(NSApp.sendAction(action, to: item.target, from: item))
        }

        XCTAssertEqual(
            performedActions,
            [.open, .preview, .copy, .copyPath, .revealInFinder, .moveToTrash]
        )
    }

    func testMoveSelectedFilesToTrashMovesAllSelectedFilesAndSelectsNext() async throws {
        viewModel.setSortOption(.fileName)
        let first = try file(named: "first.png")
        let second = try file(named: "second.png")
        let third = try file(named: "third.png")
        viewModel.selectFile(first)
        viewModel.selectFile(second, mode: .toggle)

        XCTAssertTrue(viewModel.moveSelectedFilesToTrash())
        try await waitForTrashOperation()

        XCTAssertEqual(fileActionManager.movedToTrashURLs, [first.url, second.url])
        XCTAssertEqual(viewModel.files.map(\.fileName), ["third.png"])
        XCTAssertEqual(viewModel.selectedFile?.id, third.id)
        XCTAssertEqual(viewModel.selectedFileIDs, [third.id])
    }

    func testMoveSelectedContextFileMovesAllSelectedFiles() async throws {
        viewModel.setSortOption(.fileName)
        let first = try file(named: "first.png")
        let second = try file(named: "second.png")
        let third = try file(named: "third.png")
        viewModel.selectFile(first)
        viewModel.selectFile(second, mode: .toggle)

        XCTAssertTrue(viewModel.moveFilesToTrash(for: first))
        try await waitForTrashOperation()

        XCTAssertEqual(fileActionManager.movedToTrashURLs, [first.url, second.url])
        XCTAssertEqual(viewModel.selectedFile?.id, third.id)
        XCTAssertEqual(viewModel.selectedFileIDs, [third.id])
    }

    func testMoveUnselectedContextFileMovesOnlyTargetFile() async throws {
        viewModel.setSortOption(.fileName)
        let first = try file(named: "first.png")
        let third = try file(named: "third.png")
        viewModel.selectFile(first)

        XCTAssertTrue(viewModel.moveFilesToTrash(for: third))
        try await waitForTrashOperation()

        XCTAssertEqual(fileActionManager.movedToTrashURLs, [third.url])
        XCTAssertEqual(viewModel.selectedFile?.id, first.id)
        XCTAssertEqual(viewModel.selectedFileIDs, [first.id])
    }

    func testMovingLastThenOnlyRemainingFilesUpdatesSelection() async throws {
        viewModel.setSortOption(.fileName)
        let third = try file(named: "third.png")
        viewModel.selectFile(third)

        XCTAssertTrue(viewModel.moveSelectedFilesToTrash())
        try await waitForTrashOperation()
        XCTAssertEqual(viewModel.selectedFile?.fileName, "second.png")

        XCTAssertTrue(viewModel.moveSelectedFilesToTrash())
        try await waitForTrashOperation()
        XCTAssertEqual(viewModel.selectedFile?.fileName, "first.png")

        XCTAssertTrue(viewModel.moveSelectedFilesToTrash())
        try await waitForTrashOperation()
        XCTAssertNil(viewModel.selectedFile)
        XCTAssertEqual(viewModel.displayState, .noFiles)
    }

    func testMoveToTrashFailurePreservesFilesAndSelection() async throws {
        let first = try file(named: "first.png")
        let second = try file(named: "second.png")
        viewModel.selectFile(first)
        viewModel.selectFile(second, mode: .toggle)
        fileActionManager.moveToTrashError = NSError(
            domain: "FloatPeekTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Test failure"]
        )

        XCTAssertTrue(viewModel.moveSelectedFilesToTrash())
        try await waitForTrashOperation()

        XCTAssertEqual(viewModel.files.count, 3)
        XCTAssertEqual(viewModel.selectedFileIDs, [first.id, second.id])
        XCTAssertTrue(viewModel.fileActionError?.message.contains("2") == true)
    }

    func testSingleSelectedFileCanBeRenamed() async throws {
        viewModel.setSortOption(.fileName)
        let first = try file(named: "first.png")
        viewModel.selectFile(first)

        XCTAssertEqual(viewModel.selectedFileForRenaming?.id, first.id)
        let didRename = await viewModel.renameFile(first, toBaseName: "renamed")
        XCTAssertTrue(didRename)
        try await waitForReload()

        let renamedURL = temporaryDirectory.appendingPathComponent("renamed.png")
        let resolvedRenamedURL = renamedURL.resolvingSymlinksInPath()
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.url.path))
        XCTAssertEqual(viewModel.selectedFile?.id.resolvingSymlinksInPath(), resolvedRenamedURL)
        XCTAssertEqual(
            Set(viewModel.selectedFileIDs.map { $0.resolvingSymlinksInPath() }),
            [resolvedRenamedURL]
        )
        XCTAssertEqual(
            viewModel.files.map(\.fileName),
            ["renamed.png", "second.png", "third.png"]
        )
    }

    func testRenameResortsFilesByName() async throws {
        viewModel.setSortOption(.fileName)
        let first = try file(named: "first.png")
        viewModel.selectFile(first)

        let didRename = await viewModel.renameFile(first, toBaseName: "z-last")
        XCTAssertTrue(didRename)
        try await waitForReload()

        XCTAssertEqual(
            viewModel.files.map(\.fileName),
            ["second.png", "third.png", "z-last.png"]
        )
        XCTAssertEqual(viewModel.selectedFile?.fileName, "z-last.png")
    }

    func testMultipleSelectedFilesCannotEnterRenameMode() throws {
        let first = try file(named: "first.png")
        let second = try file(named: "second.png")
        viewModel.selectFile(first)
        viewModel.selectFile(second, mode: .toggle)

        XCTAssertNil(viewModel.selectedFileForRenaming)
    }

    func testRenameFailurePreservesFileAndSelection() async throws {
        let first = try file(named: "first.png")
        viewModel.selectFile(first)
        fileActionManager.renameError = NSError(
            domain: "FloatPeekTests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Rename failure"]
        )

        let didRename = await viewModel.renameFile(first, toBaseName: "renamed")
        XCTAssertFalse(didRename)

        XCTAssertTrue(FileManager.default.fileExists(atPath: first.url.path))
        XCTAssertEqual(viewModel.selectedFile?.id, first.id)
        XCTAssertEqual(viewModel.fileActionError?.title, localized("Could not Rename File"))
        XCTAssertTrue(viewModel.fileActionError?.message.contains("Rename failure") == true)
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

    func testChangingTabFolderReloadsFilesFromNewFolder() async throws {
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

        XCTAssertEqual(viewModel.files.map(\.fileName), ["another.png"])
    }

    private func createFile(named fileName: String) throws {
        try Data("test".utf8).write(
            to: temporaryDirectory.appendingPathComponent(fileName)
        )
    }

    private func file(named fileName: String) throws -> FileItem {
        try XCTUnwrap(viewModel.files.first { $0.fileName == fileName })
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
private final class TestFilePreviewer: FilePreviewing {
    private(set) var previewedURLs: [URL] = []

    func preview(fileURL: URL) -> Bool {
        previewedURLs.append(fileURL)
        return true
    }
}
