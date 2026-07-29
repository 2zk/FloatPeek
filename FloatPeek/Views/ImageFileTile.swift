import AppKit
import SwiftUI

struct ImageFileTile: View {
    let image: ImageFile
    let isSelected: Bool
    let selectedDragURLs: [URL]
    let thumbnailHeight: CGFloat
    let thumbnailSize: CGSize
    let onSelect: (ImageBrowserViewModel.SelectionMode) -> Void
    let onOpen: () -> Void
    let onPreview: () -> Void
    let onCopy: () -> Void
    let onRevealInFinder: () -> Void
    let onCopyPath: () -> Void
    let onMoveToTrash: () -> Void

    @State private var thumbnailState: ThumbnailState = .loading

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.quaternary)

                switch thumbnailState {
                case .loaded(let thumbnail):
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                case .loading:
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 30))
                        ProgressView()
                            .controlSize(.small)
                    }
                    .foregroundStyle(.secondary)
                case .failed:
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: thumbnailHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(image.fileName)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .top)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .overlay(
            FileDragInteractionView(
                imageURL: image.url,
                isSelected: isSelected,
                selectedDragURLs: selectedDragURLs,
                onSelect: onSelect,
                onOpen: onOpen,
                onPreview: onPreview,
                onCopy: onCopy,
                onRevealInFinder: onRevealInFinder,
                onCopyPath: onCopyPath,
                onMoveToTrash: onMoveToTrash
            )
        )
        .task(id: ThumbnailRequest(image: image, size: thumbnailSize)) {
            thumbnailState = .loading

            if let loadedThumbnail = await ThumbnailProvider.shared.thumbnail(
                for: image,
                size: thumbnailSize
            ) {
                guard !Task.isCancelled else {
                    return
                }
                thumbnailState = .loaded(loadedThumbnail)
            } else {
                guard !Task.isCancelled else {
                    return
                }
                thumbnailState = .failed
            }
        }
    }
}

private struct ThumbnailRequest: Hashable {
    let image: ImageFile
    let size: CGSize
}

private enum ThumbnailState {
    case loading
    case loaded(NSImage)
    case failed
}
