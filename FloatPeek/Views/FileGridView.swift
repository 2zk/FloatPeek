import SwiftUI

enum FileGridLayout {
    static let columnWidth: CGFloat = 140
    static let columnSpacing: CGFloat = 12
    static let horizontalPadding: CGFloat = 12

    static func columnCount(forAvailableWidth width: CGFloat) -> Int {
        let contentWidth = max(width - horizontalPadding * 2, 0)
        let columnWidthWithSpacing = columnWidth + columnSpacing
        return max(Int((contentWidth + columnSpacing) / columnWidthWithSpacing), 1)
    }
}

struct FileGridView: View {
    private static let tileHorizontalPadding: CGFloat = 12
    private static let fixedThumbnailHeight: CGFloat = 96
    private static let fixedThumbnailSize = CGSize(width: 120, height: 96)
    private static let thumbnailSizeStep: CGFloat = 32

    let files: [FileItem]
    let selectedFileIDs: Set<FileItem.ID>
    let scrollTargetFileID: FileItem.ID?
    let renamingFileID: FileItem.ID?
    let columnCount: Int
    let scaleImagesWithWindow: Bool
    let availableWidth: CGFloat
    let onSelect: (FileItem, FileBrowserViewModel.SelectionMode) -> Void
    let dragURLs: (FileItem) -> [URL]
    let onAction: (FileItem, FileAction) -> Void
    let onRename: (FileItem, String) -> Void
    let onCancelRename: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(files) { file in
                        FileItemTile(
                            file: file,
                            isSelected: selectedFileIDs.contains(file.id),
                            isRenaming: renamingFileID == file.id,
                            thumbnailHeight: thumbnailHeight(for: file),
                            thumbnailSize: thumbnailSize(for: file),
                            dragURLs: {
                                dragURLs(file)
                            },
                            onSelect: { mode in
                                onSelect(file, mode)
                            },
                            onAction: { action in
                                onAction(file, action)
                            },
                            onRename: { baseName in
                                onRename(file, baseName)
                            },
                            onCancelRename: onCancelRename
                        )
                        .id(file.id)
                    }
                }
                .padding(FileGridLayout.horizontalPadding)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .onChange(of: scrollTargetFileID) { _, scrollTargetFileID in
                guard let scrollTargetFileID else {
                    return
                }

                proxy.scrollTo(scrollTargetFileID, anchor: .center)
            }
        }
    }

    private var columns: [GridItem] {
        if scaleImagesWithWindow {
            return [
                GridItem(
                    .flexible(minimum: FileGridLayout.columnWidth),
                    spacing: FileGridLayout.columnSpacing
                )
            ]
        }

        return Array(
            repeating: GridItem(
                .fixed(FileGridLayout.columnWidth),
                spacing: FileGridLayout.columnSpacing
            ),
            count: max(columnCount, 1)
        )
    }

    private func thumbnailHeight(for file: FileItem) -> CGFloat {
        guard scaleImagesWithWindow,
              file.presentationKind == .thumbnail else {
            return Self.fixedThumbnailHeight
        }

        return expandedThumbnailWidth * 3 / 4
    }

    private func thumbnailSize(for file: FileItem) -> CGSize {
        guard scaleImagesWithWindow,
              file.presentationKind == .thumbnail else {
            return Self.fixedThumbnailSize
        }

        let thumbnailHeight = thumbnailHeight(for: file)
        return CGSize(
            width: roundedThumbnailDimension(expandedThumbnailWidth),
            height: roundedThumbnailDimension(thumbnailHeight)
        )
    }

    private var expandedThumbnailWidth: CGFloat {
        let tileWidth = max(
            availableWidth - FileGridLayout.horizontalPadding * 2,
            FileGridLayout.columnWidth
        )
        return max(tileWidth - Self.tileHorizontalPadding, 1)
    }

    private func roundedThumbnailDimension(_ value: CGFloat) -> CGFloat {
        ceil(value / Self.thumbnailSizeStep) * Self.thumbnailSizeStep
    }
}
