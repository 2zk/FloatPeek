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
