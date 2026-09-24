import Foundation

enum FileItemLoaderError: Error, Equatable {
    case folderNotAccessible
}

struct FileItemLoader: @unchecked Sendable {
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

    func loadFiles(
        in folderURL: URL,
        sortedBy sortOption: FileSortOption = .addedAt
    ) throws -> [FileItem] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw FileItemLoaderError.folderNotAccessible
        }

        let fileURLs = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: Self.resourceKeys,
            options: [.skipsHiddenFiles]
        )

        var files: [FileItem] = []

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

            files.append(FileItem(
                url: fileURL,
                addedAt: resourceValues.addedToDirectoryDate ?? resourceValues.creationDate,
                modifiedAt: resourceValues.contentModificationDate
            ))
        }

        files.sort(by: sortOption)
        return files
    }

    func loadFilesAsync(
        in folderURL: URL,
        sortedBy sortOption: FileSortOption = .addedAt
    ) async throws -> [FileItem] {
        let loadTask = Task.detached(priority: .userInitiated) {
            try loadFiles(in: folderURL, sortedBy: sortOption)
        }

        return try await withTaskCancellationHandler {
            try await loadTask.value
        } onCancel: {
            loadTask.cancel()
        }
    }
}
