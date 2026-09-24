import Foundation

enum FileAction: CaseIterable {
    case open
    case preview
    case copy
    case copyPath
    case revealInFinder
    case moveToTrash
}

struct FileActionError: Equatable {
    let title: String
    let message: String
}

@MainActor
final class FileBrowserViewModel: ObservableObject {
    typealias SelectionDirection = FileSelection.Direction
    typealias SelectionMode = FileSelection.Mode

    enum DisplayState: Equatable {
        case loading
        case noFolderSelected
        case cannotAccessFolder
        case noFiles
        case loaded
    }

    @Published private(set) var folderURL: URL?
    @Published private(set) var files: [FileItem] = []
    @Published private(set) var displayState: DisplayState = .noFolderSelected
    @Published private(set) var sortOption: FileSortOption = .addedAt
    @Published private(set) var isReloading = false
    @Published private(set) var isMovingToTrash = false
    @Published private(set) var fileActionError: FileActionError?
    @Published private var selection = FileSelection()

    private var fileLoader: FileItemLoader
    private let fileOpener: FileOpening
    private let fileActionManager: FileActionHandling
    private let filePreviewer: FilePreviewing
    private let folderMonitor: FolderMonitoring
    private var shouldMonitorFolder = false
    private var isRenamingFile = false
    private var monitoringTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var reloadGeneration = 0
    private var selectionRevision = 0

    init(
        initialFolderURL: URL? = nil,
        fileLoader: FileItemLoader = FileItemLoader(
            displayedFileExtensions: AppPreferences.shared.displayedFileExtensions
        ),
        fileOpener: FileOpening = FileOpener(),
        fileActionManager: FileActionHandling = FileActionManager(),
        filePreviewer: FilePreviewing = QuickLookManager.shared,
        folderMonitor: FolderMonitoring = FolderMonitor()
    ) {
        self.fileLoader = fileLoader
        self.fileOpener = fileOpener
        self.fileActionManager = fileActionManager
        self.filePreviewer = filePreviewer
        self.folderMonitor = folderMonitor
        self.folderURL = initialFolderURL
        reload()
    }

    var selectedFileName: String {
        switch selectedFileIDs.count {
        case 0:
            return localized("None")
        case 1:
            return selectedFile?.fileName ?? selectedFiles.first?.fileName ?? localized("None")
        default:
            return localizedFormat("%d files", selectedFileIDs.count)
        }
    }

    var selectedFile: FileItem? {
        guard let focusedID = selection.focusedID else {
            return nil
        }
        return files.first { $0.id == focusedID }
    }

    var selectedFileIDs: Set<FileItem.ID> {
        selection.selectedIDs
    }

    var selectedFiles: [FileItem] {
        files.filter { selectedFileIDs.contains($0.id) }
    }

    var selectedFileForRenaming: FileItem? {
        guard selectedFileIDs.count == 1 else {
            return nil
        }
        return selectedFile
    }

    var isShowingFileActionError: Bool {
        get { fileActionError != nil }
        set {
            if !newValue {
                fileActionError = nil
            }
        }
    }

    func setFolderURL(_ folderURL: URL?) {
        guard self.folderURL != folderURL else {
            return
        }

        self.folderURL = folderURL
        reload()

        if shouldMonitorFolder {
            restartMonitoring()
        }
    }

    func startMonitoring() {
        shouldMonitorFolder = true
        restartMonitoring()
    }

    func setDisplayedFileExtensions(_ displayedFileExtensions: Set<String>) {
        guard fileLoader.displayedFileExtensions != displayedFileExtensions else {
            return
        }

        fileLoader.displayedFileExtensions = displayedFileExtensions
        reload()

        if shouldMonitorFolder {
            restartMonitoring()
        }
    }

    func stopMonitoring() {
        shouldMonitorFolder = false
        monitoringTask?.cancel()
        let folderMonitor = folderMonitor
        monitoringTask = Task {
            await folderMonitor.stopMonitoring()
        }
    }

    func reload() {
        reloadTask?.cancel()
        reloadGeneration += 1
        let generation = reloadGeneration

        guard let folderURL else {
            isReloading = false
            files = []
            selection.clear()
            displayState = .noFolderSelected
            return
        }

        isReloading = true
        if files.isEmpty {
            displayState = .loading
        }

        let fileLoader = fileLoader
        let requestedSortOption = sortOption
        reloadTask = Task { [weak self] in
            do {
                var loadedFiles = try await fileLoader.loadFilesAsync(
                    in: folderURL,
                    sortedBy: requestedSortOption
                )

                guard let self,
                      !Task.isCancelled,
                      generation == self.reloadGeneration,
                      self.folderURL == folderURL else {
                    return
                }

                if self.sortOption != requestedSortOption {
                    loadedFiles.sort(by: self.sortOption)
                }
                self.files = loadedFiles
                self.reconcileSelection()
                self.displayState = loadedFiles.isEmpty ? .noFiles : .loaded
                self.isReloading = false
            } catch is CancellationError {
                guard let self, generation == self.reloadGeneration else {
                    return
                }
                self.isReloading = false
            } catch {
                guard let self,
                      generation == self.reloadGeneration,
                      self.folderURL == folderURL else {
                    return
                }
                self.clearFilesForLoadFailure()
            }
        }
    }

    func selectFile(_ file: FileItem, mode: SelectionMode = .replace) {
        changeSelection { selection, orderedIDs in
            selection.select(file.id, mode: mode, orderedIDs: orderedIDs)
            return true
        }
    }

    @discardableResult
    func selectAllFiles() -> Bool {
        changeSelection { selection, orderedIDs in
            selection.selectAll(orderedIDs: orderedIDs)
        }
    }

    func setSortOption(_ sortOption: FileSortOption) {
        guard self.sortOption != sortOption else {
            return
        }

        self.sortOption = sortOption
        files.sort(by: sortOption)
        reconcileSelection()
    }

    @discardableResult
    func moveSelection(
        _ direction: SelectionDirection,
        columnCount: Int,
        extendingSelection: Bool = false
    ) -> Bool {
        changeSelection { selection, orderedIDs in
            selection.move(
                direction,
                columnCount: columnCount,
                orderedIDs: orderedIDs,
                extendingSelection: extendingSelection
            )
        }
    }

    /// 右クリックメニューなどから、指定したファイルを起点に操作を実行する
    func performFileAction(_ action: FileAction, for file: FileItem) {
        switch action {
        case .open:
            openFile(file)
        case .preview:
            previewFile(file)
        case .copy:
            copyFiles(for: file)
        case .copyPath:
            copyPaths(for: file)
        case .revealInFinder:
            revealInFinder(file)
        case .moveToTrash:
            moveFilesToTrash(for: file)
        }
    }

    func openFile(_ file: FileItem) {
        selectFile(file)
        fileOpener.open(file.url)
    }

    @discardableResult
    func previewFile(_ file: FileItem) -> Bool {
        if !selectedFileIDs.contains(file.id) {
            selectFile(file)
        }
        return filePreviewer.preview(fileURL: file.url)
    }

    /// 選択中のファイルなら選択中の全ファイル、そうでなければ指定したファイルだけを対象にする
    func actionURLs(for file: FileItem) -> [URL] {
        actionFiles(for: file).map(\.url)
    }

    @discardableResult
    func copySelectedFiles() -> Bool {
        fileActionManager.copyFiles(selectedFiles.map(\.url))
    }

    @discardableResult
    func copyFiles(for file: FileItem) -> Bool {
        fileActionManager.copyFiles(actionURLs(for: file))
    }

    @discardableResult
    func copyPaths(for file: FileItem) -> Bool {
        fileActionManager.copyPaths(actionURLs(for: file))
    }

    @discardableResult
    func revealInFinder(_ file: FileItem) -> Bool {
        fileActionManager.revealInFinder(actionURLs(for: file))
    }

    @discardableResult
    func moveSelectedFilesToTrash() -> Bool {
        moveToTrash(selectedFiles)
    }

    @discardableResult
    func moveFilesToTrash(for file: FileItem) -> Bool {
        moveToTrash(actionFiles(for: file))
    }

    @discardableResult
    func renameFile(_ file: FileItem, toBaseName baseName: String) async -> Bool {
        guard !isRenamingFile,
              files.contains(where: { $0.id == file.id }) else {
            return false
        }

        let newFileName = file.fileName(withBaseName: baseName)
        let requestedFolderURL = folderURL
        let fileActionManager = fileActionManager

        isRenamingFile = true
        fileActionError = nil

        do {
            let renamedURL = try await fileActionManager.renameFile(
                file.url,
                toFileName: newFileName
            )
            isRenamingFile = false

            guard folderURL == requestedFolderURL,
                  let fileIndex = files.firstIndex(where: { $0.id == file.id }) else {
                return true
            }

            files[fileIndex] = FileItem(
                url: renamedURL,
                addedAt: file.addedAt,
                modifiedAt: file.modifiedAt
            )
            files.sort(by: sortOption)
            changeSelection { selection, orderedIDs in
                selection.select(renamedURL, mode: .replace, orderedIDs: orderedIDs)
                return true
            }
            displayState = .loaded
            reload()
            return true
        } catch {
            isRenamingFile = false
            fileActionError = FileActionError(
                title: localized("Could not Rename File"),
                message: localizedFormat(
                    "%@ could not be renamed.\n%@",
                    file.fileName,
                    renameErrorDescription(error)
                )
            )
            return false
        }
    }

    private func moveToTrash(_ targetFiles: [FileItem]) -> Bool {
        guard !isMovingToTrash else {
            return true
        }

        guard !targetFiles.isEmpty else {
            return false
        }

        let targetIDs = Set(targetFiles.map(\.id))
        let requestedFolderURL = folderURL
        let focusedIDAtRequest = selection.focusedID
        let originalFocusedIndex = focusedIDAtRequest
            .flatMap { focusedID in files.firstIndex(where: { $0.id == focusedID }) }
            ?? files.firstIndex(where: { targetIDs.contains($0.id) })
            ?? 0
        let selectionRevisionAtRequest = selectionRevision
        let fileActionManager = fileActionManager

        isMovingToTrash = true
        fileActionError = nil

        Task { [weak self] in
            do {
                try await fileActionManager.moveToTrash(targetFiles.map(\.url))

                guard let self else {
                    return
                }

                self.isMovingToTrash = false
                guard self.folderURL == requestedFolderURL else {
                    return
                }

                self.removeRecycledFiles(
                    withIDs: targetIDs,
                    originalFocusedIndex: originalFocusedIndex,
                    shouldAdvanceSelection: focusedIDAtRequest.map(targetIDs.contains) == true
                        && self.selectionRevision == selectionRevisionAtRequest
                )
                self.reload()
            } catch {
                guard let self else {
                    return
                }

                self.isMovingToTrash = false
                self.fileActionError = Self.moveToTrashError(
                    for: targetFiles,
                    error: error
                )

                if self.folderURL == requestedFolderURL {
                    self.reload()
                }
            }
        }

        return true
    }

    func dismissFileActionError() {
        fileActionError = nil
    }

    private static func moveToTrashError(
        for targetFiles: [FileItem],
        error: Error
    ) -> FileActionError {
        let message: String
        if targetFiles.count == 1, let targetFile = targetFiles.first {
            message = localizedFormat(
                "%@ could not be moved to the Trash.\n%@",
                targetFile.fileName,
                error.localizedDescription
            )
        } else {
            message = localizedFormat(
                "%d files could not be moved to the Trash.\n%@",
                targetFiles.count,
                error.localizedDescription
            )
        }
        return FileActionError(title: localized("Could not Move to Trash"), message: message)
    }

    private func renameErrorDescription(_ error: Error) -> String {
        switch error as? FileRenameError {
        case .emptyName:
            return localized("A file name is required.")
        case .invalidName:
            return localized("The file name is not valid.")
        case .destinationExists:
            return localized("A file with that name already exists.")
        case nil:
            return error.localizedDescription
        }
    }

    private func reconcileSelection() {
        selection.reconcile(orderedIDs: files.map(\.id))
    }

    /// 利用者の操作による選択変更を反映し、変更があれば選択の世代を進める。
    /// ゴミ箱移動後に選択を自動で進めてよいかの判定に世代を使う。
    @discardableResult
    private func changeSelection(
        _ change: (inout FileSelection, _ orderedIDs: [FileItem.ID]) -> Bool
    ) -> Bool {
        let didChange = change(&selection, files.map(\.id))
        if didChange {
            selectionRevision += 1
        }
        return didChange
    }

    private func clearFilesForLoadFailure() {
        files = []
        selection.clear()
        displayState = .cannotAccessFolder
        isReloading = false
    }

    private func restartMonitoring() {
        monitoringTask?.cancel()
        let folderMonitor = folderMonitor
        let folderURL = folderURL
        let shouldMonitorFolder = shouldMonitorFolder
        let displayedFileExtensions = fileLoader.displayedFileExtensions

        monitoringTask = Task { [weak self] in
            await folderMonitor.stopMonitoring()

            guard shouldMonitorFolder,
                  let folderURL,
                  !Task.isCancelled else {
                return
            }

            await folderMonitor.startMonitoring(
                folderURL: folderURL,
                displayedFileExtensions: displayedFileExtensions
            ) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.reload()
                }
            }
        }
    }

    private func actionFiles(for file: FileItem) -> [FileItem] {
        guard selectedFileIDs.contains(file.id) else {
            return [file]
        }

        return selectedFiles
    }

    private func removeRecycledFiles(
        withIDs recycledIDs: Set<FileItem.ID>,
        originalFocusedIndex: Int,
        shouldAdvanceSelection: Bool
    ) {
        files.removeAll { recycledIDs.contains($0.id) }

        changeSelection { selection, orderedIDs in
            if !shouldAdvanceSelection {
                selection.reconcile(orderedIDs: orderedIDs)
            } else if orderedIDs.isEmpty {
                selection.clear()
            } else {
                let nextIndex = min(originalFocusedIndex, orderedIDs.count - 1)
                selection.select(orderedIDs[nextIndex], mode: .replace, orderedIDs: orderedIDs)
            }
            return true
        }
        displayState = files.isEmpty ? .noFiles : .loaded
    }

}
