import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localization: LocalizationManager

    @StateObject private var viewModel: SettingsViewModel
    @State private var draggedTabID: FolderTab.ID?

    init(viewModel: SettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            tabsSection

            Divider()

            languageSection

            Divider()

            shortcutSection
            actionButtons
        }
        .padding(20)
        .frame(width: 560)
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
                    .frame(maxWidth: .infinity, minHeight: 64)
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
                .frame(maxHeight: 260)
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
        Group {
            VStack(alignment: .leading, spacing: 6) {
                Text(localization.localized("Global Shortcut"))
                    .font(.headline)
                Text(localization.localized("Click the field, then press the shortcut to show or hide FloatPeek."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ShortcutRecorderView(shortcut: $viewModel.shortcut)
                .frame(width: 260, height: 48)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
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
                    Image(systemName: "minus")
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
