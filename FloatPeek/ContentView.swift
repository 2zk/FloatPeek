import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = FileBrowserViewModel()
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var tabManager: FolderTabManager
    @EnvironmentObject private var appCoordinator: AppCoordinator
    @EnvironmentObject private var updateManager: UpdateManager
    @State private var gridColumnCount = 1
    @State private var scrollTargetFileID: FileItem.ID?
    @State private var renamingFileID: FileItem.ID?

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
                        FileGridView(
                            files: viewModel.files,
                            selectedFileIDs: viewModel.selectedFileIDs,
                            scrollTargetFileID: scrollTargetFileID,
                            renamingFileID: renamingFileID,
                            columnCount: displayedGridColumnCount,
                            scaleImagesWithWindow: preferences.scaleImagesWithWindow,
                            availableWidth: geometry.size.width,
                            onSelect: { file, mode in
                                scrollTargetFileID = nil
                                viewModel.selectFile(file, mode: mode)
                            },
                            dragURLs: viewModel.actionURLs(for:),
                            onAction: { file, action in
                                viewModel.performFileAction(action, for: file)
                            },
                            onRename: { file, baseName in
                                renamingFileID = nil
                                Task {
                                    await viewModel.renameFile(file, toBaseName: baseName)
                                }
                            },
                            onCancelRename: {
                                renamingFileID = nil
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
                case .noFiles:
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
        .onChange(of: viewModel.selectedFile) { _, selectedFile in
            guard let selectedFile else {
                QuickLookManager.shared.closePreviewIfVisible()
                return
            }

            QuickLookManager.shared.updatePreviewIfVisible(fileURL: selectedFile.url)
        }
        .onChange(of: viewModel.folderURL) { _, _ in
            renamingFileID = nil
            ThumbnailProvider.shared.clearCache()
        }
        .onChange(of: viewModel.files) { _, files in
            if let renamingFileID,
               !files.contains(where: { $0.id == renamingFileID }) {
                self.renamingFileID = nil
            }
        }
        .onChange(of: preferences.displayedFileExtensions) { _, displayedFileExtensions in
            viewModel.setDisplayedFileExtensions(displayedFileExtensions)
        }
        .onAppear {
            viewModel.setDisplayedFileExtensions(preferences.displayedFileExtensions)
            syncSelectedTab()
            viewModel.startMonitoring()
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
        .onChange(of: appCoordinator.isWindowVisible) { _, isWindowVisible in
            if isWindowVisible {
                viewModel.reload()
                viewModel.startMonitoring()
            } else {
                viewModel.stopMonitoring()
            }
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

        guard renamingFileID == nil else {
            return false
        }

        switch key {
        case .return:
            guard let selectedFile = viewModel.selectedFileForRenaming else {
                return !viewModel.selectedFileIDs.isEmpty
            }

            renamingFileID = selectedFile.id
            return true
        case .escape:
            WindowManager.shared.hideWindow()
            return true
        case .space:
            return previewSelectedFile()
        case .arrow(let direction, let extendingSelection):
            let didMove = viewModel.moveSelection(
                direction,
                columnCount: displayedGridColumnCount,
                extendingSelection: extendingSelection
            )
            updateScrollTargetAfterKeyboardSelection(didMove)
            return didMove
        case .selectAll:
            return viewModel.selectAllFiles()
        case .copy:
            return viewModel.copySelectedFiles()
        case .moveToTrash:
            return viewModel.moveSelectedFilesToTrash()
        case .selectNextTab:
            return tabManager.selectNextTab()
        case .selectPreviousTab:
            return tabManager.selectPreviousTab()
        }
    }

    @discardableResult
    private func previewSelectedFile() -> Bool {
        guard let selectedFile = viewModel.selectedFile else {
            return false
        }

        return QuickLookManager.shared.togglePreview(fileURL: selectedFile.url)
    }

    private func updateScrollTargetAfterKeyboardSelection(_ didMove: Bool) {
        guard didMove else {
            return
        }

        scrollTargetFileID = viewModel.selectedFile?.id
    }

    private func updateGridColumnCount(for width: CGFloat) {
        gridColumnCount = FileGridLayout.columnCount(forAvailableWidth: width)
    }

    private var displayedGridColumnCount: Int {
        preferences.scaleImagesWithWindow ? 1 : gridColumnCount
    }

    private func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(
            preferences: preferences,
            localization: localization,
            tabManager: tabManager,
            updateSettings: updateManager,
            onReloadCurrentTab: viewModel.reload,
            onToggleWindow: WindowManager.shared.toggleWindow
        )
    }

    private func syncSelectedTab() {
        viewModel.setFolderURL(tabManager.selectedTab?.folderURL)
    }
}
