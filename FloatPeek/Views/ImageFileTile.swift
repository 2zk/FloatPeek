import AppKit
import SwiftUI

struct ImageFileTile: View {
    let image: ImageFile
    let isSelected: Bool
    let isRenaming: Bool
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
    let onRename: (String) -> Void
    let onCancelRename: () -> Void

    @State private var thumbnailState: ThumbnailState = .loading
    @State private var renameDraft: String
    @FocusState private var isRenameFieldFocused: Bool

    init(
        image: ImageFile,
        isSelected: Bool,
        isRenaming: Bool,
        selectedDragURLs: [URL],
        thumbnailHeight: CGFloat,
        thumbnailSize: CGSize,
        onSelect: @escaping (ImageBrowserViewModel.SelectionMode) -> Void,
        onOpen: @escaping () -> Void,
        onPreview: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onRevealInFinder: @escaping () -> Void,
        onCopyPath: @escaping () -> Void,
        onMoveToTrash: @escaping () -> Void,
        onRename: @escaping (String) -> Void,
        onCancelRename: @escaping () -> Void
    ) {
        self.image = image
        self.isSelected = isSelected
        self.isRenaming = isRenaming
        self.selectedDragURLs = selectedDragURLs
        self.thumbnailHeight = thumbnailHeight
        self.thumbnailSize = thumbnailSize
        self.onSelect = onSelect
        self.onOpen = onOpen
        self.onPreview = onPreview
        self.onCopy = onCopy
        self.onRevealInFinder = onRevealInFinder
        self.onCopyPath = onCopyPath
        self.onMoveToTrash = onMoveToTrash
        self.onRename = onRename
        self.onCancelRename = onCancelRename
        _renameDraft = State(initialValue: image.url.deletingPathExtension().lastPathComponent)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.quaternary)

                if image.presentationKind == .fileIcon {
                    Image(
                        nsImage: ThumbnailProvider.shared.fileIcon(
                            forFileExtension: image.url.pathExtension
                        )
                    )
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                } else {
                    thumbnailContent
                }
            }
            .frame(height: thumbnailHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            fileNameContent
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
            .allowsHitTesting(!isRenaming)
        )
        .task(id: thumbnailRequest) {
            guard image.presentationKind == .thumbnail else {
                return
            }

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
        .onChange(of: isRenaming) { _, isRenaming in
            guard isRenaming else {
                return
            }

            renameDraft = image.url.deletingPathExtension().lastPathComponent
            focusRenameField()
        }
    }

    @ViewBuilder
    private var fileNameContent: some View {
        if isRenaming {
            HStack(spacing: 0) {
                TextField("", text: $renameDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($isRenameFieldFocused)
                    .onSubmit {
                        onRename(renameDraft)
                    }
                    .onExitCommand {
                        onCancelRename()
                    }

                if !image.url.pathExtension.isEmpty {
                    Text(".\(image.url.pathExtension)")
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .top)
            .onAppear {
                focusRenameField()
            }
            .onChange(of: isRenameFieldFocused) { wasFocused, isFocused in
                if wasFocused, !isFocused, isRenaming {
                    onRename(renameDraft)
                }
            }
        } else {
            Text(image.fileName)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .top)
        }
    }

    private func focusRenameField() {
        isRenameFieldFocused = true
        DispatchQueue.main.async {
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        }
    }

    @ViewBuilder
    private var thumbnailContent: some View {
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

    private var thumbnailRequest: ThumbnailRequest? {
        guard image.presentationKind == .thumbnail else {
            return nil
        }
        return ThumbnailRequest(image: image, size: thumbnailSize)
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
