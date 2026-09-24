import Foundation

enum ImageFileLoaderError: Error, Equatable {
    case folderNotAccessible
}

struct ImageFileLoader: @unchecked Sendable {
    static let supportedExtensions = AppSettings.allSupportedFileExtensions
    private static let resourceKeys: [URLResourceKey] = [
        .addedToDirectoryDateKey,
        .creationDateKey,
        .contentModificationDateKey,
        .isRegularFileKey
    ]

    private let fileManager: FileManager
    var displayedFileExtensions: Set<String>

    init(
        fileManager: FileManager = .default,
        displayedFileExtensions: Set<String> = AppSettings.defaultDisplayedFileExtensions
    ) {
        self.fileManager = fileManager
        self.displayedFileExtensions = displayedFileExtensions
    }

    func loadImages(
        in folderURL: URL,
        sortedBy sortOption: FileSortOption = .addedAt
    ) throws -> [ImageFile] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ImageFileLoaderError.folderNotAccessible
        }

        let fileURLs = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: Self.resourceKeys,
            options: [.skipsHiddenFiles]
        )

        var images: [ImageFile] = []

        for fileURL in fileURLs {
            try Task.checkCancellation()

            guard displayedFileExtensions.contains(fileURL.pathExtension.lowercased()) else {
                continue
            }

            guard let resourceValues = try? fileURL.resourceValues(
                forKeys: Set(Self.resourceKeys)
            ) else {
                continue
            }

            guard resourceValues.isRegularFile == true else {
                continue
            }

            images.append(ImageFile(
                url: fileURL,
                addedAt: resourceValues.addedToDirectoryDate ?? resourceValues.creationDate,
                modifiedAt: resourceValues.contentModificationDate
            ))
        }

        images.sort(by: sortOption)
        return images
    }

    func loadImagesAsync(
        in folderURL: URL,
        sortedBy sortOption: FileSortOption = .addedAt
    ) async throws -> [ImageFile] {
        let loadTask = Task.detached(priority: .userInitiated) {
            try loadImages(in: folderURL, sortedBy: sortOption)
        }

        return try await withTaskCancellationHandler {
            try await loadTask.value
        } onCancel: {
            loadTask.cancel()
        }
    }
}
