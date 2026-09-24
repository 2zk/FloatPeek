import Foundation

enum FilePresentationKind: Equatable {
    case thumbnail
    case fileIcon
}

struct ImageFile: Identifiable, Hashable {
    let id: URL
    let url: URL
    let fileName: String
    let addedAt: Date?
    let modifiedAt: Date?

    var presentationKind: FilePresentationKind {
        AppSettings.allThumbnailFileExtensions.contains(fileExtension.lowercased())
            ? .thumbnail
            : .fileIcon
    }

    /// 拡張子を除いたファイル名
    var baseName: String {
        url.deletingPathExtension().lastPathComponent
    }

    var fileExtension: String {
        url.pathExtension
    }

    /// 拡張子を維持したまま、拡張子を除いた部分だけを差し替えたファイル名を返す
    func fileName(withBaseName baseName: String) -> String {
        fileExtension.isEmpty ? baseName : "\(baseName).\(fileExtension)"
    }

    init(url: URL, addedAt: Date?, modifiedAt: Date?) {
        self.id = url
        self.url = url
        self.fileName = url.lastPathComponent
        self.addedAt = addedAt
        self.modifiedAt = modifiedAt
    }
}

enum FileSortOption: String, CaseIterable, Identifiable {
    case addedAt
    case modifiedAt
    case fileName

    var id: Self {
        self
    }

    @MainActor
    var displayName: String {
        switch self {
        case .addedAt:
            return localized("Date Added")
        case .modifiedAt:
            return localized("Date Modified")
        case .fileName:
            return localized("File Name")
        }
    }
}

extension FileSortOption {
    func areInIncreasingOrder(_ lhs: ImageFile, _ rhs: ImageFile) -> Bool {
        switch self {
        case .addedAt:
            return Self.dateDescendingThenName(lhs.addedAt, rhs.addedAt, lhs: lhs, rhs: rhs)
        case .modifiedAt:
            return Self.dateDescendingThenName(lhs.modifiedAt, rhs.modifiedAt, lhs: lhs, rhs: rhs)
        case .fileName:
            return Self.nameAscending(lhs, rhs)
        }
    }

    private static func dateDescendingThenName(
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
            return nameAscending(lhs, rhs)
        }
    }

    private static func nameAscending(_ lhs: ImageFile, _ rhs: ImageFile) -> Bool {
        lhs.fileName.localizedStandardCompare(rhs.fileName) == .orderedAscending
    }
}

extension Array where Element == ImageFile {
    mutating func sort(by sortOption: FileSortOption) {
        sort(by: sortOption.areInIncreasingOrder)
    }
}
