import SwiftUI

struct ImageGridView: View {
    private static let columnWidth: CGFloat = 140
    private static let columnSpacing: CGFloat = 12
    private static let horizontalPadding: CGFloat = 12
    private static let tileHorizontalPadding: CGFloat = 12
    private static let fixedThumbnailHeight: CGFloat = 96
    private static let fixedThumbnailSize = CGSize(width: 120, height: 96)
    private static let thumbnailSizeStep: CGFloat = 32

    let images: [ImageFile]
    let selectedImageIDs: Set<ImageFile.ID>
    let selectedImages: [ImageFile]
    let scrollTargetImageID: ImageFile.ID?
    let columnCount: Int
    let scaleImagesWithWindow: Bool
    let availableWidth: CGFloat
    let onSelect: (ImageFile, ImageBrowserViewModel.SelectionMode) -> Void
    let onOpen: (ImageFile) -> Void
    let onPreview: (ImageFile) -> Void
    let onCopy: (ImageFile) -> Void
    let onRevealInFinder: (ImageFile) -> Void
    let onCopyPath: (ImageFile) -> Void
    let onMoveToTrash: (ImageFile) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(images) { image in
                        ImageFileTile(
                            image: image,
                            isSelected: selectedImageIDs.contains(image.id),
                            selectedDragURLs: selectedDragURLs(for: image),
                            thumbnailHeight: thumbnailHeight(for: image),
                            thumbnailSize: thumbnailSize(for: image),
                            onSelect: { mode in
                                onSelect(image, mode)
                            },
                            onOpen: {
                                onOpen(image)
                            },
                            onPreview: {
                                onPreview(image)
                            },
                            onCopy: {
                                onCopy(image)
                            },
                            onRevealInFinder: {
                                onRevealInFinder(image)
                            },
                            onCopyPath: {
                                onCopyPath(image)
                            },
                            onMoveToTrash: {
                                onMoveToTrash(image)
                            }
                        )
                        .id(image.id)
                    }
                }
                .padding(Self.horizontalPadding)
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
                    .flexible(minimum: Self.columnWidth),
                    spacing: Self.columnSpacing
                )
            ]
        }

        return Array(
            repeating: GridItem(.fixed(Self.columnWidth), spacing: Self.columnSpacing),
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
            availableWidth - Self.horizontalPadding * 2,
            Self.columnWidth
        )
        return max(tileWidth - Self.tileHorizontalPadding, 1)
    }

    private func roundedThumbnailDimension(_ value: CGFloat) -> CGFloat {
        ceil(value / Self.thumbnailSizeStep) * Self.thumbnailSizeStep
    }

    private func selectedDragURLs(for image: ImageFile) -> [URL] {
        guard selectedImageIDs.contains(image.id) else {
            return [image.url]
        }

        return selectedImages.map(\.url)
    }
}
