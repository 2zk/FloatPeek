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
final class ImageBrowserViewModel: ObservableObject {
    typealias SelectionDirection = ImageSelection.Direction
    typealias SelectionMode = ImageSelection.Mode

    enum DisplayState: Equatable {
        case loading
        case noFolderSelected
        case cannotAccessFolder
        case noImages
        case loaded
    }

    @Published private(set) var folderURL: URL?
    @Published private(set) var images: [ImageFile] = []
    @Published private(set) var displayState: DisplayState = .noFolderSelected
    @Published private(set) var sortOption: FileSortOption = .addedAt
    @Published private(set) var isReloading = false
    @Published private(set) var isMovingToTrash = false
    @Published private(set) var fileActionError: FileActionError?
    @Published private var selection = ImageSelection()

    private var imageFileLoader: ImageFileLoader
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
        imageFileLoader: ImageFileLoader = ImageFileLoader(),
        fileOpener: FileOpening = FileOpener(),
        fileActionManager: FileActionHandling = FileActionManager(),
        filePreviewer: FilePreviewing = QuickLookManager.shared,
        folderMonitor: FolderMonitoring = FolderMonitor()
    ) {
        self.imageFileLoader = imageFileLoader
        self.fileOpener = fileOpener
        self.fileActionManager = fileActionManager
        self.filePreviewer = filePreviewer
        self.folderMonitor = folderMonitor
        self.folderURL = initialFolderURL
        reload()
    }

    var selectedFileName: String {
        switch selectedImageIDs.count {
        case 0:
            return localized("None")
        case 1:
            return selectedImage?.fileName ?? selectedImages.first?.fileName ?? localized("None")
        default:
            return LocalizationManager.shared.localizedFormat("%d files", selectedImageIDs.count)
        }
    }

    var selectedImage: ImageFile? {
        guard let focusedID = selection.focusedID else {
            return nil
        }
        return images.first { $0.id == focusedID }
    }

    var selectedImageIDs: Set<ImageFile.ID> {
        selection.selectedIDs
    }

    var selectedImages: [ImageFile] {
        images.filter { selectedImageIDs.contains($0.id) }
    }

    var selectedImageForRenaming: ImageFile? {
        guard selectedImageIDs.count == 1 else {
            return nil
        }
        return selectedImage
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
        guard imageFileLoader.displayedFileExtensions != displayedFileExtensions else {
            return
        }

        imageFileLoader.displayedFileExtensions = displayedFileExtensions
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
            images = []
            selection.clear()
            displayState = .noFolderSelected
            return
        }

        isReloading = true
        if images.isEmpty {
            displayState = .loading
        }

        let imageFileLoader = imageFileLoader
        let requestedSortOption = sortOption
        reloadTask = Task { [weak self] in
            do {
                var loadedImages = try await imageFileLoader.loadImagesAsync(
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
                    loadedImages.sort(by: self.sortOption)
                }
                self.images = loadedImages
                self.reconcileSelection()
                self.displayState = loadedImages.isEmpty ? .noImages : .loaded
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
                self.clearImagesForLoadFailure()
            }
        }
    }

    func selectImage(_ image: ImageFile, mode: SelectionMode = .replace) {
        changeSelection { selection, orderedIDs in
            selection.select(image.id, mode: mode, orderedIDs: orderedIDs)
            return true
        }
    }

    @discardableResult
    func selectAllImages() -> Bool {
        changeSelection { selection, orderedIDs in
            selection.selectAll(orderedIDs: orderedIDs)
        }
    }

    func setSortOption(_ sortOption: FileSortOption) {
        guard self.sortOption != sortOption else {
            return
        }

        self.sortOption = sortOption
        images.sort(by: sortOption)
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
    func performFileAction(_ action: FileAction, for image: ImageFile) {
        switch action {
        case .open:
            openImage(image)
        case .preview:
            previewImage(image)
        case .copy:
            copyImages(for: image)
        case .copyPath:
            copyPaths(for: image)
        case .revealInFinder:
            revealInFinder(image)
        case .moveToTrash:
            moveImagesToTrash(for: image)
        }
    }

    func openImage(_ image: ImageFile) {
        selectImage(image)
        fileOpener.open(image.url)
    }

    @discardableResult
    func previewImage(_ image: ImageFile) -> Bool {
        if !selectedImageIDs.contains(image.id) {
            selectImage(image)
        }
        return filePreviewer.preview(fileURL: image.url)
    }

    /// 選択中のファイルなら選択中の全ファイル、そうでなければ指定したファイルだけを対象にする
    func actionURLs(for image: ImageFile) -> [URL] {
        actionImages(for: image).map(\.url)
    }

    @discardableResult
    func copySelectedImages() -> Bool {
        fileActionManager.copyFiles(selectedImages.map(\.url))
    }

    @discardableResult
    func copyImages(for image: ImageFile) -> Bool {
        fileActionManager.copyFiles(actionURLs(for: image))
    }

    @discardableResult
    func copyPaths(for image: ImageFile) -> Bool {
        fileActionManager.copyPaths(actionURLs(for: image))
    }

    @discardableResult
    func revealInFinder(_ image: ImageFile) -> Bool {
        fileActionManager.revealInFinder(actionURLs(for: image))
    }

    @discardableResult
    func moveSelectedImagesToTrash() -> Bool {
        moveToTrash(selectedImages)
    }

    @discardableResult
    func moveImagesToTrash(for image: ImageFile) -> Bool {
        moveToTrash(actionImages(for: image))
    }

    @discardableResult
    func renameImage(_ image: ImageFile, toBaseName baseName: String) async -> Bool {
        guard !isRenamingFile,
              images.contains(where: { $0.id == image.id }) else {
            return false
        }

        let newFileName = image.fileName(withBaseName: baseName)
        let requestedFolderURL = folderURL
        let fileActionManager = fileActionManager

        isRenamingFile = true
        fileActionError = nil

        do {
            let renamedURL = try await fileActionManager.renameFile(
                image.url,
                toFileName: newFileName
            )
            isRenamingFile = false

            guard folderURL == requestedFolderURL,
                  let imageIndex = images.firstIndex(where: { $0.id == image.id }) else {
                return true
            }

            images[imageIndex] = ImageFile(
                url: renamedURL,
                addedAt: image.addedAt,
                modifiedAt: image.modifiedAt
            )
            images.sort(by: sortOption)
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
                message: LocalizationManager.shared.localizedFormat(
                    "%@ could not be renamed.\n%@",
                    image.fileName,
                    renameErrorDescription(error)
                )
            )
            return false
        }
    }

    private func moveToTrash(_ targetImages: [ImageFile]) -> Bool {
        guard !isMovingToTrash else {
            return true
        }

        guard !targetImages.isEmpty else {
            return false
        }

        let targetIDs = Set(targetImages.map(\.id))
        let requestedFolderURL = folderURL
        let focusedIDAtRequest = selection.focusedID
        let originalFocusedIndex = focusedIDAtRequest
            .flatMap { focusedID in images.firstIndex(where: { $0.id == focusedID }) }
            ?? images.firstIndex(where: { targetIDs.contains($0.id) })
            ?? 0
        let selectionRevisionAtRequest = selectionRevision
        let fileActionManager = fileActionManager

        isMovingToTrash = true
        fileActionError = nil

        Task { [weak self] in
            do {
                try await fileActionManager.moveToTrash(targetImages.map(\.url))

                guard let self else {
                    return
                }

                self.isMovingToTrash = false
                guard self.folderURL == requestedFolderURL else {
                    return
                }

                self.removeRecycledImages(
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
                    for: targetImages,
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
        for targetImages: [ImageFile],
        error: Error
    ) -> FileActionError {
        let message: String
        if targetImages.count == 1, let targetImage = targetImages.first {
            message = LocalizationManager.shared.localizedFormat(
                "%@ could not be moved to the Trash.\n%@",
                targetImage.fileName,
                error.localizedDescription
            )
        } else {
            message = LocalizationManager.shared.localizedFormat(
                "%d files could not be moved to the Trash.\n%@",
                targetImages.count,
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
        selection.reconcile(orderedIDs: images.map(\.id))
    }

    /// 利用者の操作による選択変更を反映し、変更があれば選択の世代を進める。
    /// ゴミ箱移動後に選択を自動で進めてよいかの判定に世代を使う。
    @discardableResult
    private func changeSelection(
        _ change: (inout ImageSelection, _ orderedIDs: [ImageFile.ID]) -> Bool
    ) -> Bool {
        let didChange = change(&selection, images.map(\.id))
        if didChange {
            selectionRevision += 1
        }
        return didChange
    }

    private func clearImagesForLoadFailure() {
        images = []
        selection.clear()
        displayState = .cannotAccessFolder
        isReloading = false
    }

    private func restartMonitoring() {
        monitoringTask?.cancel()
        let folderMonitor = folderMonitor
        let folderURL = folderURL
        let shouldMonitorFolder = shouldMonitorFolder
        let displayedFileExtensions = imageFileLoader.displayedFileExtensions

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

    private func actionImages(for image: ImageFile) -> [ImageFile] {
        guard selectedImageIDs.contains(image.id) else {
            return [image]
        }

        return selectedImages
    }

    private func removeRecycledImages(
        withIDs recycledIDs: Set<ImageFile.ID>,
        originalFocusedIndex: Int,
        shouldAdvanceSelection: Bool
    ) {
        images.removeAll { recycledIDs.contains($0.id) }

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
        displayState = images.isEmpty ? .noImages : .loaded
    }

}
