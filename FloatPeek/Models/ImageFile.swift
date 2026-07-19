import Foundation

struct ImageFile: Identifiable, Hashable {
    let id: URL
    let url: URL
    let fileName: String
    let addedAt: Date?
    let modifiedAt: Date?

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
