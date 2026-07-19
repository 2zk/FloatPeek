import Foundation

enum ImageFileLoaderError: Error, Equatable {
    case folderNotAccessible
}

struct ImageFileLoader: @unchecked Sendable {
    static let supportedExtensions: Set<String> = [
        "jpg",
        "jpeg",
        "png",
        "gif",
        "heic",
        "pdf"
    ]

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
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
            includingPropertiesForKeys: [
                .addedToDirectoryDateKey,
                .creationDateKey,
                .contentModificationDateKey,
                .isRegularFileKey
            ],
            options: [.skipsHiddenFiles]
        )

        var images: [ImageFile] = []

        for fileURL in fileURLs {
            try Task.checkCancellation()

            guard Self.supportedExtensions.contains(fileURL.pathExtension.lowercased()) else {
                continue
            }

            guard let resourceValues = try? fileURL.resourceValues(forKeys: [
                .addedToDirectoryDateKey,
                .creationDateKey,
                .contentModificationDateKey,
                .isRegularFileKey
            ]) else {
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

        return images.sorted { lhs, rhs in
            Self.sort(lhs, rhs, by: sortOption)
        }
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

    static func sort(
        _ lhs: ImageFile,
        _ rhs: ImageFile,
        by sortOption: FileSortOption
    ) -> Bool {
        switch sortOption {
        case .addedAt:
            return sortByDateDescendingThenName(lhs.addedAt, rhs.addedAt, lhs: lhs, rhs: rhs)
        case .modifiedAt:
            return sortByDateDescendingThenName(lhs.modifiedAt, rhs.modifiedAt, lhs: lhs, rhs: rhs)
        case .fileName:
            return sortByNameAscending(lhs, rhs)
        }
    }

    private static func sortByDateDescendingThenName(
        _ lhsDate: Date?,
        _ rhsDate: Date?,
        lhs: ImageFile,
        rhs: ImageFile
    ) -> Bool {
        switch (lhsDate, rhsDate) {
        case let (leftDate?, rightDate?) where leftDate != rightDate:
            return leftDate > rightDate
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return sortByNameAscending(lhs, rhs)
        }
    }

    private static func sortByNameAscending(_ lhs: ImageFile, _ rhs: ImageFile) -> Bool {
        lhs.fileName.localizedStandardCompare(rhs.fileName) == .orderedAscending
    }
}
