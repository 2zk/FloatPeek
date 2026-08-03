import Foundation

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
    @Published private(set) var fileActionErrorMessage: String?
    @Published private var selection = ImageSelection()

    private var imageFileLoader: ImageFileLoader
    private let fileOpener: FileOpening
    private let fileActionManager: FileActionHandling
    private let folderMonitor: FolderMonitoring
    private var shouldMonitorFolder = false
    private var monitoringTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var reloadGeneration = 0
    private var selectionRevision = 0

    init(
        initialFolderURL: URL? = nil,
        imageFileLoader: ImageFileLoader = ImageFileLoader(),
        fileOpener: FileOpening = FileOpener(),
        fileActionManager: FileActionHandling = FileActionManager(),
        folderMonitor: FolderMonitoring = FolderMonitor()
    ) {
        self.imageFileLoader = imageFileLoader
        self.fileOpener = fileOpener
        self.fileActionManager = fileActionManager
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
                    loadedImages.sort { lhs, rhs in
                        ImageFileLoader.sort(lhs, rhs, by: self.sortOption)
                    }
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
        selection.select(image.id, mode: mode, orderedIDs: images.map(\.id))
        selectionRevision += 1
    }

    @discardableResult
    func selectAllImages() -> Bool {
        let didSelect = selection.selectAll(orderedIDs: images.map(\.id))
        if didSelect {
            selectionRevision += 1
        }
        return didSelect
    }

    func setSortOption(_ sortOption: FileSortOption) {
        guard self.sortOption != sortOption else {
            return
        }

        self.sortOption = sortOption
        images.sort { lhs, rhs in
            ImageFileLoader.sort(lhs, rhs, by: sortOption)
        }
        reconcileSelection()
    }

    @discardableResult
    func moveSelection(
        _ direction: SelectionDirection,
        columnCount: Int,
        extendingSelection: Bool = false
    ) -> Bool {
        let didMove = selection.move(
            direction,
            columnCount: columnCount,
            orderedIDs: images.map(\.id),
            extendingSelection: extendingSelection
        )
        if didMove {
            selectionRevision += 1
        }
        return didMove
    }

    func openImage(_ image: ImageFile) {
        selection.select(image.id, mode: .replace, orderedIDs: images.map(\.id))
        selectionRevision += 1
        fileOpener.open(image.url)
    }

    @discardableResult
    func openSelectedImage() -> Bool {
        guard let selectedImage else {
            return false
        }

        return fileOpener.open(selectedImage.url)
    }

    @discardableResult
    func copySelectedImages() -> Bool {
        fileActionManager.copyFiles(selectedImages.map(\.url))
    }

    @discardableResult
    func copyImages(for image: ImageFile) -> Bool {
        fileActionManager.copyFiles(actionImages(for: image).map(\.url))
    }

    @discardableResult
    func copyPaths(for image: ImageFile) -> Bool {
        fileActionManager.copyPaths(actionImages(for: image).map(\.url))
    }

    @discardableResult
    func revealInFinder(_ image: ImageFile) -> Bool {
        fileActionManager.revealInFinder(actionImages(for: image).map(\.url))
    }

    @discardableResult
    func moveSelectedImagesToTrash() -> Bool {
        moveToTrash(selectedImages)
    }

    @discardableResult
    func moveImagesToTrash(for image: ImageFile) -> Bool {
        moveToTrash(actionImages(for: image))
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
        fileActionErrorMessage = nil

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
                if targetImages.count == 1, let targetImage = targetImages.first {
                    self.fileActionErrorMessage = LocalizationManager.shared.localizedFormat(
                        "%@ could not be moved to the Trash.\n%@",
                        targetImage.fileName,
                        error.localizedDescription
                    )
                } else {
                    self.fileActionErrorMessage = LocalizationManager.shared.localizedFormat(
                        "%d files could not be moved to the Trash.\n%@",
                        targetImages.count,
                        error.localizedDescription
                    )
                }

                if self.folderURL == requestedFolderURL {
                    self.reload()
                }
            }
        }

        return true
    }

    func dismissFileActionError() {
        fileActionErrorMessage = nil
    }

    private func reconcileSelection() {
        selection.reconcile(orderedIDs: images.map(\.id))
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

        if shouldAdvanceSelection {
            if images.isEmpty {
                selection.clear()
            } else {
                let nextIndex = min(originalFocusedIndex, images.count - 1)
                selection.select(
                    images[nextIndex].id,
                    mode: .replace,
                    orderedIDs: images.map(\.id)
                )
            }
        } else {
            reconcileSelection()
        }

        selectionRevision += 1
        displayState = images.isEmpty ? .noImages : .loaded
    }

}
