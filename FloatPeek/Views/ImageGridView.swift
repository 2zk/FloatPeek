import SwiftUI

enum ImageGridLayout {
    static let columnWidth: CGFloat = 140
    static let columnSpacing: CGFloat = 12
    static let horizontalPadding: CGFloat = 12

    static func columnCount(forAvailableWidth width: CGFloat) -> Int {
        let contentWidth = max(width - horizontalPadding * 2, 0)
        let columnWidthWithSpacing = columnWidth + columnSpacing
        return max(Int((contentWidth + columnSpacing) / columnWidthWithSpacing), 1)
    }
}

struct ImageGridView: View {
    private static let tileHorizontalPadding: CGFloat = 12
    private static let fixedThumbnailHeight: CGFloat = 96
    private static let fixedThumbnailSize = CGSize(width: 120, height: 96)
    private static let thumbnailSizeStep: CGFloat = 32

    let images: [ImageFile]
    let selectedImageIDs: Set<ImageFile.ID>
    let scrollTargetImageID: ImageFile.ID?
    let renamingImageID: ImageFile.ID?
    let columnCount: Int
    let scaleImagesWithWindow: Bool
    let availableWidth: CGFloat
    let onSelect: (ImageFile, ImageBrowserViewModel.SelectionMode) -> Void
    let dragURLs: (ImageFile) -> [URL]
    let onAction: (ImageFile, FileAction) -> Void
    let onRename: (ImageFile, String) -> Void
    let onCancelRename: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(images) { image in
                        ImageFileTile(
                            image: image,
                            isSelected: selectedImageIDs.contains(image.id),
                            isRenaming: renamingImageID == image.id,
                            thumbnailHeight: thumbnailHeight(for: image),
                            thumbnailSize: thumbnailSize(for: image),
                            dragURLs: {
                                dragURLs(image)
                            },
                            onSelect: { mode in
                                onSelect(image, mode)
                            },
                            onAction: { action in
                                onAction(image, action)
                            },
                            onRename: { baseName in
                                onRename(image, baseName)
                            },
                            onCancelRename: onCancelRename
                        )
                        .id(image.id)
                    }
                }
                .padding(ImageGridLayout.horizontalPadding)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .onChange(of: scrollTargetImageID) { _, scrollTargetImageID in
                guard let scrollTargetImageID else {
                    return
                }

                proxy.scrollTo(scrollTargetImageID, anchor: .center)
            }
        }
    }

    private var columns: [GridItem] {
        if scaleImagesWithWindow {
            return [
                GridItem(
                    .flexible(minimum: ImageGridLayout.columnWidth),
                    spacing: ImageGridLayout.columnSpacing
                )
            ]
        }

        return Array(
            repeating: GridItem(
                .fixed(ImageGridLayout.columnWidth),
                spacing: ImageGridLayout.columnSpacing
            ),
            count: max(columnCount, 1)
        )
    }

    private func thumbnailHeight(for image: ImageFile) -> CGFloat {
        guard scaleImagesWithWindow,
              image.presentationKind == .thumbnail else {
            return Self.fixedThumbnailHeight
        }

        return expandedThumbnailWidth * 3 / 4
    }

    private func thumbnailSize(for image: ImageFile) -> CGSize {
        guard scaleImagesWithWindow,
              image.presentationKind == .thumbnail else {
            return Self.fixedThumbnailSize
        }

        let thumbnailHeight = thumbnailHeight(for: image)
        return CGSize(
            width: roundedThumbnailDimension(expandedThumbnailWidth),
            height: roundedThumbnailDimension(thumbnailHeight)
        )
    }

    private var expandedThumbnailWidth: CGFloat {
        let tileWidth = max(
            availableWidth - ImageGridLayout.horizontalPadding * 2,
            ImageGridLayout.columnWidth
        )
        return max(tileWidth - Self.tileHorizontalPadding, 1)
    }

    private func roundedThumbnailDimension(_ value: CGFloat) -> CGFloat {
        ceil(value / Self.thumbnailSizeStep) * Self.thumbnailSizeStep
    }
}
