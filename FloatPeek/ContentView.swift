import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ImageBrowserViewModel()
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var tabManager: FolderTabManager
    @EnvironmentObject private var appCoordinator: AppCoordinator
    @EnvironmentObject private var updateManager: UpdateManager
    @State private var gridColumnCount = 1
    @State private var scaleImagesWithWindow = AppSettings.loadScaleImagesWithWindow()
    @State private var scrollTargetImageID: ImageFile.ID?
    @State private var renamingImageID: ImageFile.ID?

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
                            scrollTargetImageID: scrollTargetImageID,
                            renamingImageID: renamingImageID,
                            columnCount: displayedGridColumnCount,
                            scaleImagesWithWindow: scaleImagesWithWindow,
                            availableWidth: geometry.size.width,
                            onSelect: { image, mode in
                                scrollTargetImageID = nil
                                viewModel.selectImage(image, mode: mode)
                            },
                            dragURLs: viewModel.actionURLs(for:),
                            onAction: { image, action in
                                viewModel.performFileAction(action, for: image)
                            },
                            onRename: { image, baseName in
                                renamingImageID = nil
                                Task {
                                    await viewModel.renameImage(image, toBaseName: baseName)
                                }
                            },
                            onCancelRename: {
                                renamingImageID = nil
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
                        message: localization.localized(
                            "Enable file extensions in Settings or choose another folder."
                        )
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
            renamingImageID = nil
            ThumbnailProvider.shared.clearCache()
        }
        .onChange(of: viewModel.images) { _, images in
            if let renamingImageID,
               !images.contains(where: { $0.id == renamingImageID }) {
                self.renamingImageID = nil
            }
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
            SettingsView(
                viewModel: makeSettingsViewModel(),
                updateManager: updateManager
            )
        }
        .alert(
            viewModel.fileActionError?.title ?? "",
            isPresented: $viewModel.isShowingFileActionError,
            presenting: viewModel.fileActionError
        ) { _ in
            Button(localization.localized("OK")) {
                viewModel.dismissFileActionError()
            }
        } message: { error in
            Text(error.message)
        }
    }

    @discardableResult
    private func handleKeyDown(_ key: HandledKey) -> Bool {
        guard !appCoordinator.isShowingSettings else {
            return false
        }

        guard renamingImageID == nil else {
            return false
        }

        switch key {
        case .return:
            guard let selectedImage = viewModel.selectedImageForRenaming else {
                return !viewModel.selectedImageIDs.isEmpty
            }

            renamingImageID = selectedImage.id
            return true
        case .escape:
            WindowManager.shared.hideWindow()
            return true
        case .space:
            return previewSelectedImage()
        case .arrow(let direction, let extendingSelection):
            let didMove = viewModel.moveSelection(
                direction,
                columnCount: displayedGridColumnCount,
                extendingSelection: extendingSelection
            )
            updateScrollTargetAfterKeyboardSelection(didMove)
            return didMove
        case .selectAll:
            return viewModel.selectAllImages()
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

    private func updateScrollTargetAfterKeyboardSelection(_ didMove: Bool) {
        guard didMove else {
            return
        }

        scrollTargetImageID = viewModel.selectedImage?.id
    }

    private func updateGridColumnCount(for width: CGFloat) {
        gridColumnCount = ImageGridLayout.columnCount(forAvailableWidth: width)
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
            quickLookBackgroundColor: AppSettings.loadQuickLookBackgroundColor(),
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
            },
            onQuickLookBackgroundColorChange: { backgroundColor in
                QuickLookManager.shared.applyBackgroundColor(backgroundColor)
            },
            automaticallyChecksForUpdates: updateManager.automaticallyChecksForUpdates,
            onAutomaticallyChecksForUpdatesChange: { isEnabled in
                updateManager.setAutomaticallyChecksForUpdates(isEnabled)
            },
            updateCheckFrequency: updateManager.updateCheckFrequency,
            onUpdateCheckFrequencyChange: { frequency in
                updateManager.setUpdateCheckFrequency(frequency)
            }
        )
    }

    private func syncSelectedTab() {
        viewModel.setFolderURL(tabManager.selectedTab?.folderURL)
    }
}
