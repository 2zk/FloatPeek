import SwiftUI

struct ContentView: View {
    private static let gridColumnWidth: CGFloat = 140
    private static let gridColumnSpacing: CGFloat = 12
    private static let gridHorizontalPadding: CGFloat = 12

    @StateObject private var viewModel = ImageBrowserViewModel()
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var tabManager: FolderTabManager
    @EnvironmentObject private var appCoordinator: AppCoordinator
    @State private var gridColumnCount = 1
    @State private var scaleImagesWithWindow = AppSettings.loadScaleImagesWithWindow()

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(
                tabs: tabManager.tabs,
                selectedTabID: tabManager.selectedTabID,
                sortOption: viewModel.sortOption,
                onSelectTab: tabManager.selectTab,
                onSortChange: viewModel.setSortOption
            )

            Divider()

            Group {
                switch viewModel.displayState {
                case .loading:
                    ProgressView(localization.localized("Loading…"))
                case .loaded:
                    GeometryReader { geometry in
                        ImageGridView(
                            images: viewModel.images,
                            selectedImageIDs: viewModel.selectedImageIDs,
                            selectedImages: viewModel.selectedImages,
                            selectedImageID: viewModel.selectedImage?.id,
                            columnCount: displayedGridColumnCount,
                            scaleImagesWithWindow: scaleImagesWithWindow,
                            availableWidth: geometry.size.width,
                            onSelect: { image, mode in
                                viewModel.selectImage(image, mode: mode)
                            },
                            onOpen: viewModel.openImage,
                            onPreview: { image in
                                previewImage(image)
                            },
                            onCopy: { image in
                                viewModel.copyImages(for: image)
                            },
                            onRevealInFinder: { image in
                                viewModel.revealInFinder(image)
                            },
                            onCopyPath: { image in
                                viewModel.copyPaths(for: image)
                            },
                            onMoveToTrash: { image in
                                viewModel.moveImagesToTrash(for: image)
                            }
                        )
                        .onAppear {
                            updateGridColumnCount(for: geometry.size.width)
                        }
                        .onChange(of: geometry.size.width) { _, newWidth in
                            updateGridColumnCount(for: newWidth)
                        }
                    }
                case .noFolderSelected:
                    if tabManager.tabs.isEmpty {
                        StateMessageView(
                            title: localization.localized("No tabs configured"),
                            message: localization.localized("Add a tab in Settings.")
                        )
                    } else {
                        StateMessageView(
                            title: localization.localized("No folder selected"),
                            message: localization.localized("Choose a folder for this tab in Settings.")
                        )
                    }
                case .cannotAccessFolder:
                    StateMessageView(
                        title: localization.localized("Cannot access folder"),
                        message: localization.localized("Choose another folder.")
                    )
                case .noImages:
                    StateMessageView(
                        title: localization.localized("No supported files found"),
                        message: localization.localized("Supported formats: jpg, jpeg, png, gif, heic, pdf.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Text(localization.localized("Selected:"))
                    .foregroundStyle(.secondary)
                Text(viewModel.selectedFileName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(
            KeyboardEventBridge(onKeyDown: handleKeyDown)
                .frame(width: 0, height: 0)
        )
        .background(
            WindowAccessor { window in
                WindowManager.shared.configure(window: window)
            }
            .frame(width: 0, height: 0)
        )
        .onChange(of: viewModel.selectedImage) { _, selectedImage in
            guard let selectedImage else {
                QuickLookManager.shared.closePreviewIfVisible()
                return
            }

            QuickLookManager.shared.updatePreviewIfVisible(fileURL: selectedImage.url)
        }
        .onChange(of: viewModel.folderURL) { _, _ in
            ThumbnailProvider.shared.clearCache()
        }
        .onAppear {
            syncSelectedTab()
            viewModel.startMonitoring()
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
        .onChange(of: appCoordinator.windowVisibleRevision) { _, _ in
            viewModel.reload()
            viewModel.startMonitoring()
        }
        .onChange(of: appCoordinator.windowHiddenRevision) { _, _ in
            viewModel.stopMonitoring()
        }
        .onChange(of: tabManager.selectedTabID) { _, _ in
            syncSelectedTab()
        }
        .onChange(of: tabManager.tabs) { _, _ in
            syncSelectedTab()
        }
        .sheet(isPresented: $appCoordinator.isShowingSettings) {
            SettingsView(viewModel: makeSettingsViewModel())
        }
        .alert(
            localization.localized("Could not Move to Trash"),
            isPresented: Binding(
                get: { viewModel.fileActionErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.dismissFileActionError()
                    }
                }
            )
        ) {
            Button(localization.localized("OK")) {
                viewModel.dismissFileActionError()
            }
        } message: {
            Text(viewModel.fileActionErrorMessage ?? "")
        }
    }

    @discardableResult
    private func handleKeyDown(_ key: HandledKey) -> Bool {
        guard !appCoordinator.isShowingSettings else {
            return false
        }

        switch key {
        case .return:
            return viewModel.openSelectedImage()
        case .escape:
            WindowManager.shared.hideWindow()
            return true
        case .space:
            return previewSelectedImage()
        case .leftArrow(let extendingSelection):
            return viewModel.moveSelection(
                .left,
                columnCount: displayedGridColumnCount,
                extendingSelection: extendingSelection
            )
        case .rightArrow(let extendingSelection):
            return viewModel.moveSelection(
                .right,
                columnCount: displayedGridColumnCount,
                extendingSelection: extendingSelection
            )
        case .upArrow(let extendingSelection):
            return viewModel.moveSelection(
                .up,
                columnCount: displayedGridColumnCount,
                extendingSelection: extendingSelection
            )
        case .downArrow(let extendingSelection):
            return viewModel.moveSelection(
                .down,
                columnCount: displayedGridColumnCount,
                extendingSelection: extendingSelection
            )
        case .copy:
            return viewModel.copySelectedImages()
        case .moveToTrash:
            return viewModel.moveSelectedImagesToTrash()
        case .selectNextTab:
            return tabManager.selectNextTab()
        case .selectPreviousTab:
            return tabManager.selectPreviousTab()
        }
    }

    @discardableResult
    private func previewSelectedImage() -> Bool {
        guard let selectedImage = viewModel.selectedImage else {
            return false
        }

        return QuickLookManager.shared.togglePreview(fileURL: selectedImage.url)
    }

    @discardableResult
    private func previewImage(_ image: ImageFile) -> Bool {
        if !viewModel.selectedImageIDs.contains(image.id) {
            viewModel.selectImage(image)
        }
        return QuickLookManager.shared.preview(fileURL: image.url)
    }

    private func updateGridColumnCount(for width: CGFloat) {
        let contentWidth = max(width - Self.gridHorizontalPadding * 2, 0)
        let columnWidthWithSpacing = Self.gridColumnWidth + Self.gridColumnSpacing
        gridColumnCount = max(Int((contentWidth + Self.gridColumnSpacing) / columnWidthWithSpacing), 1)
    }

    private var displayedGridColumnCount: Int {
        scaleImagesWithWindow ? 1 : gridColumnCount
    }

    private func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(
            shortcut: HotKeyManager.shared.currentShortcut(),
            language: localization.language,
            scaleImagesWithWindow: scaleImagesWithWindow,
            displayedFileExtensions: AppSettings.loadDisplayedFileExtensions(),
            tabs: tabManager.tabs,
            selectedTabID: tabManager.selectedTabID,
            localization: localization,
            tabManager: tabManager,
            folderChooser: FolderManager(),
            onReloadCurrentTab: viewModel.reload,
            onToggleWindow: WindowManager.shared.toggleWindow,
            onScaleImagesWithWindowChange: { isEnabled in
                scaleImagesWithWindow = isEnabled
            },
            onDisplayedFileExtensionsChange: { displayedFileExtensions in
                viewModel.setDisplayedFileExtensions(displayedFileExtensions)
            }
        )
    }

    private func syncSelectedTab() {
        viewModel.setFolderURL(tabManager.selectedTab?.folderURL)
    }
}
