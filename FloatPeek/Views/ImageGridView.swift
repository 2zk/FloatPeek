import SwiftUI

struct ImageGridView: View {
    private static let columnWidth: CGFloat = 140
    private static let columnSpacing: CGFloat = 12

    let images: [ImageFile]
    let selectedImageIDs: Set<ImageFile.ID>
    let selectedImages: [ImageFile]
    let selectedImageID: ImageFile.ID?
    let columnCount: Int
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
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .onChange(of: selectedImageID) { _, selectedImageID in
                guard let selectedImageID else {
                    return
                }

                proxy.scrollTo(selectedImageID, anchor: .center)
            }
        }
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(Self.columnWidth), spacing: Self.columnSpacing),
            count: max(columnCount, 1)
        )
    }

    private func selectedDragURLs(for image: ImageFile) -> [URL] {
        guard selectedImageIDs.contains(image.id) else {
            return [image.url]
        }

        return selectedImages.map(\.url)
    }
}
