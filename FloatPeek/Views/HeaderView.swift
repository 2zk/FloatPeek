import SwiftUI

struct HeaderView: View {
    @EnvironmentObject private var localization: LocalizationManager

    let tabs: [FolderTab]
    let selectedTabID: FolderTab.ID?
    let sortOption: FileSortOption
    let onSelectTab: (FolderTab.ID) -> Void
    let onSortChange: (FileSortOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if tabs.isEmpty {
                Text(localization.localized("No tabs configured"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 4) {
                        ForEach(tabs) { tab in
                            Button {
                                onSelectTab(tab.id)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder")
                                    Text(tab.displayName)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                                .background {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(
                                            tab.id == selectedTabID
                                                ? Color.accentColor.opacity(0.2)
                                                : Color.clear
                                        )
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: tabListHeight)
            }

            Divider()

            HStack(spacing: 6) {
                Text(localization.localized("Sort"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(
                    localization.localized("Sort"),
                    selection: Binding(
                        get: { sortOption },
                        set: { sortOption in
                            onSortChange(sortOption)
                        }
                    )
                ) {
                    ForEach(FileSortOption.allCases) { sortOption in
                        Text(sortOption.displayName).tag(sortOption)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)

                Spacer()
            }
        }
        .padding(12)
    }

    private var tabListHeight: CGFloat {
        min(CGFloat(tabs.count) * 32, 160)
    }
}
