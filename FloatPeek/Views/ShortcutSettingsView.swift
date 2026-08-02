import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    private static let settingsSize = CGSize(width: 840, height: 720)
    private static let foldersColumnWidth: CGFloat = 440
    private static let detailsColumnWidth: CGFloat = 336
    private static let extensionColumns = Array(
        repeating: GridItem(.flexible(minimum: 60), spacing: 8, alignment: .leading),
        count: 4
    )

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localization: LocalizationManager

    @StateObject private var viewModel: SettingsViewModel
    @ObservedObject private var updateManager: UpdateManager
    @State private var draggedTabID: FolderTab.ID?

    init(viewModel: SettingsViewModel, updateManager: UpdateManager) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _updateManager = ObservedObject(wrappedValue: updateManager)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 24) {
                tabsSection
                    .frame(width: Self.foldersColumnWidth)
                    .frame(maxHeight: .infinity, alignment: .top)

                detailsColumn
                    .frame(width: Self.detailsColumnWidth)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(20)
            .frame(maxHeight: .infinity)

            Divider()

            actionButtons
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(width: Self.settingsSize.width, height: Self.settingsSize.height)
    }

    private var detailsColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            displaySection

            Divider()

            languageSection

            Divider()

            shortcutSection

            Divider()

            updatesSection
        }
    }

    private var tabsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(localization.localized("Tabs"))
                    .font(.headline)

                Spacer()

                Button {
                    viewModel.addTab()
                } label: {
                    Label(localization.localized("Add Tab"), systemImage: "plus")
                }
            }

            if viewModel.tabs.isEmpty {
                Text(localization.localized("No tabs configured"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 8) {
                        ForEach($viewModel.tabs) { $tab in
                            tabSettingsRow(tab: $tab)
                                .onDrop(
                                    of: [UTType.text],
                                    delegate: FolderReorderDropDelegate(
                                        targetID: tab.id,
                                        draggedTabID: $draggedTabID,
                                        onMove: { sourceID, targetID in
                                            withAnimation {
                                                viewModel.moveTab(id: sourceID, to: targetID)
                                            }
                                        }
                                    )
                                )
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }

            Button {
                viewModel.reloadCurrentTab()
            } label: {
                Label(
                    localization.localized("Reload Current Tab"),
                    systemImage: "arrow.clockwise"
                )
            }
            .disabled(!viewModel.canReloadCurrentTab)
        }
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localization.localized("Display"))
                .font(.headline)

            Toggle(
                localization.localized("Scale images and PDFs with window width"),
                isOn: $viewModel.scaleImagesWithWindow
            )

            Text(localization.localized("Displayed File Extensions"))
                .font(.subheadline)

            fileExtensionGroup(
                title: localization.localized("Images and PDFs"),
                fileExtensions: AppSettings.thumbnailFileExtensions
            )

            fileExtensionGroup(
                title: localization.localized("Other Files"),
                fileExtensions: AppSettings.iconFileExtensions
            )

            Text(localization.localized("Quick Look Background"))
                .font(.subheadline)

            ColorPicker(
                localization.localized("Background Color"),
                selection: quickLookBackgroundColorBinding,
                supportsOpacity: false
            )
        }
    }

    private var languageSection: some View {
        HStack {
            Text(localization.localized("Language"))
                .font(.headline)

            Spacer()

            Picker(
                localization.localized("Language"),
                selection: $viewModel.language
            ) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .labelsHidden()
            .frame(width: 180)
        }
    }

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localization.localized("Global Shortcut"))
                .font(.headline)
            Text(localization.localized("Click the field, then press the shortcut to show or hide FloatPeek."))
                .font(.caption)
                .foregroundStyle(.secondary)

            ShortcutRecorderView(shortcut: $viewModel.shortcut)
                .frame(width: 260, height: 48)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localization.localized("Updates"))
                .font(.headline)

            HStack {
                Toggle(
                    localization.localized("Automatically check for updates"),
                    isOn: $viewModel.automaticallyChecksForUpdates
                )
                .toggleStyle(.checkbox)

                Spacer()

                Picker(
                    localization.localized("Update Check Frequency"),
                    selection: $viewModel.updateCheckFrequency
                ) {
                    ForEach(UpdateCheckFrequency.allCases) { frequency in
                        Text(localization.localized(frequency.localizationKey)).tag(frequency)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
                .disabled(!viewModel.automaticallyChecksForUpdates)
            }

            Button(localization.localized("Check Now")) {
                updateManager.checkForUpdates()
            }
            .disabled(!updateManager.canCheckForUpdates)

            if let lastUpdateCheckDate = updateManager.lastUpdateCheckDate {
                HStack(spacing: 4) {
                    Text(localization.localized("Last checked"))
                    Text(lastUpdateCheckDate, format: .dateTime.year().month().day().hour().minute())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text(localization.localized("Not checked yet"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(localization.localizedFormat("Version %@", appVersion))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actionButtons: some View {
        HStack {
            Button(localization.localized("Restore Default")) {
                viewModel.restoreDefaultShortcut()
            }

            Spacer()

            Button(localization.localized("Cancel")) {
                dismiss()
            }

            Button(localization.localized("Save")) {
                if viewModel.save() {
                    dismiss()
                }
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func tabSettingsRow(tab: Binding<FolderTab>) -> some View {
        let tabID = tab.wrappedValue.id
        let isSelected = viewModel.selectedTabID == tabID

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 28)
                    .contentShape(Rectangle())
                    .help(localization.localized("Drag to reorder"))
                    .onDrag {
                        draggedTabID = tabID
                        return NSItemProvider(object: tabID.uuidString as NSString)
                    }

                Button {
                    viewModel.selectTab(id: tabID)
                } label: {
                    Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                }
                .buttonStyle(.plain)
                .help(localization.localized("Show this tab"))

                TextField(localization.localized("Tab Name"), text: tab.name)

                Button(localization.localized("Choose Folder…")) {
                    viewModel.chooseFolder(for: tabID)
                }

                Button {
                    viewModel.removeTab(id: tabID)
                } label: {
                    Image(systemName: "xmark")
                }
                .help(localization.localized("Remove Tab"))
            }

            Text(
                tab.wrappedValue.folderPath.isEmpty
                    ? localization.localized("No folder selected")
                    : tab.wrappedValue.folderPath
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.leading, 54)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
        }
    }

    private func displayedFileExtensionBinding(_ fileExtension: String) -> Binding<Bool> {
        Binding(
            get: {
                viewModel.displayedFileExtensions.contains(fileExtension)
            },
            set: { isDisplayed in
                viewModel.setDisplayedFileExtensions(
                    [fileExtension],
                    isDisplayed: isDisplayed
                )
            }
        )
    }

    private func fileExtensionGroup(
        title: String,
        fileExtensions: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(localization.localized("Select All")) {
                    viewModel.setDisplayedFileExtensions(
                        fileExtensions,
                        isDisplayed: true
                    )
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(
                    Set(fileExtensions).isSubset(
                        of: viewModel.displayedFileExtensions
                    )
                )

                Button(localization.localized("Deselect All")) {
                    viewModel.setDisplayedFileExtensions(
                        fileExtensions,
                        isDisplayed: false
                    )
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(
                    Set(fileExtensions).isDisjoint(
                        with: viewModel.displayedFileExtensions
                    )
                )
            }

            LazyVGrid(
                columns: Self.extensionColumns,
                alignment: .leading,
                spacing: 4
            ) {
                ForEach(fileExtensions, id: \.self) { fileExtension in
                    Toggle(
                        ".\(fileExtension)",
                        isOn: displayedFileExtensionBinding(fileExtension)
                    )
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var quickLookBackgroundColorBinding: Binding<Color> {
        Binding(
            get: {
                Color(
                    .sRGB,
                    red: viewModel.quickLookBackgroundColor.red,
                    green: viewModel.quickLookBackgroundColor.green,
                    blue: viewModel.quickLookBackgroundColor.blue,
                    opacity: 1
                )
            },
            set: { color in
                guard let color = NSColor(color).usingColorSpace(.sRGB) else {
                    return
                }

                viewModel.quickLookBackgroundColor.red = color.redComponent
                viewModel.quickLookBackgroundColor.green = color.greenComponent
                viewModel.quickLookBackgroundColor.blue = color.blueComponent
            }
        )
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

}

private struct FolderReorderDropDelegate: DropDelegate {
    let targetID: FolderTab.ID
    @Binding var draggedTabID: FolderTab.ID?
    let onMove: (FolderTab.ID, FolderTab.ID) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedTabID,
              draggedTabID != targetID else {
            return
        }

        onMove(draggedTabID, targetID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedTabID = nil
        return true
    }
}
