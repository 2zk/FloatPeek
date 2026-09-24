import XCTest
@testable import FloatPeek

final class FileItemLoaderTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testLoadFilesFiltersSupportedExtensionsCaseInsensitively() throws {
        try createFile(named: "a.JPG", modifiedAt: Date(timeIntervalSince1970: 10))
        try createFile(named: "b.png", modifiedAt: Date(timeIntervalSince1970: 20))
        try createFile(named: "c.PDF", modifiedAt: Date(timeIntervalSince1970: 30))
        try createFile(named: "c.txt", modifiedAt: Date(timeIntervalSince1970: 30))

        let files = try FileItemLoader().loadFiles(in: temporaryDirectory, sortedBy: .modifiedAt)

        XCTAssertEqual(files.map(\.fileName), ["c.PDF", "b.png", "a.JPG"])
    }

    func testLoadFilesFiltersDeselectedExtensions() throws {
        try createFile(named: "a.jpg", modifiedAt: Date(timeIntervalSince1970: 10))
        try createFile(named: "b.png", modifiedAt: Date(timeIntervalSince1970: 20))

        let files = try FileItemLoader(
            displayedFileExtensions: ["png"]
        ).loadFiles(in: temporaryDirectory)

        XCTAssertEqual(files.map(\.fileName), ["b.png"])
    }

    func testLoadFilesIncludesSelectedDocumentExtensionCaseInsensitively() throws {
        try createFile(named: "notes.TXT", modifiedAt: Date(timeIntervalSince1970: 10))
        try createFile(named: "report.DOCX", modifiedAt: Date(timeIntervalSince1970: 20))

        let files = try FileItemLoader(
            displayedFileExtensions: ["txt", "docx"]
        ).loadFiles(in: temporaryDirectory, sortedBy: .fileName)

        XCTAssertEqual(files.map(\.fileName), ["notes.TXT", "report.DOCX"])
    }

    func testFilePresentationKindUsesExtensionCaseInsensitively() {
        XCTAssertEqual(makeFileItem(named: "image.WEBP").presentationKind, .thumbnail)
        XCTAssertEqual(makeFileItem(named: "report.DOCX").presentationKind, .fileIcon)
        XCTAssertEqual(makeFileItem(named: "unknown.bin").presentationKind, .fileIcon)
    }

    func testLoadFilesSortsByModifiedDateDescendingThenNameAscending() throws {
        let newerDate = Date(timeIntervalSince1970: 20)
        let olderDate = Date(timeIntervalSince1970: 10)
        try createFile(named: "z.png", modifiedAt: olderDate)
        try createFile(named: "b.png", modifiedAt: newerDate)
        try createFile(named: "a.png", modifiedAt: newerDate)

        let files = try FileItemLoader().loadFiles(in: temporaryDirectory, sortedBy: .modifiedAt)

        XCTAssertEqual(files.map(\.fileName), ["a.png", "b.png", "z.png"])
    }

    func testSortsByAddedDateDescendingThenNameAscending() {
        let newerDate = Date(timeIntervalSince1970: 20)
        let olderDate = Date(timeIntervalSince1970: 10)
        let files = [
            makeFileItem(named: "z.png", addedAt: olderDate),
            makeFileItem(named: "b.png", addedAt: newerDate),
            makeFileItem(named: "a.png", addedAt: newerDate)
        ]
        .sorted(by: FileSortOption.addedAt.areInIncreasingOrder)

        XCTAssertEqual(files.map(\.fileName), ["a.png", "b.png", "z.png"])
    }

    func testLoadFilesSortsByFileNameAscending() throws {
        try createFile(named: "z.png", modifiedAt: Date(timeIntervalSince1970: 30))
        try createFile(named: "a.png", modifiedAt: Date(timeIntervalSince1970: 20))
        try createFile(named: "c.PDF", modifiedAt: Date(timeIntervalSince1970: 10))

        let files = try FileItemLoader().loadFiles(in: temporaryDirectory, sortedBy: .fileName)

        XCTAssertEqual(files.map(\.fileName), ["a.png", "c.PDF", "z.png"])
    }

    func testLoadFilesThrowsForMissingFolder() {
        let missingFolder = temporaryDirectory.appendingPathComponent("missing", isDirectory: true)

        XCTAssertThrowsError(try FileItemLoader().loadFiles(in: missingFolder)) { error in
            XCTAssertEqual(error as? FileItemLoaderError, .folderNotAccessible)
        }
    }

    func testFileItemSplitsBaseNameAndKeepsExtensionWhenRenaming() {
        let file = FileItem(url: URL(fileURLWithPath: "/tmp/photo.v2.PNG"), addedAt: nil, modifiedAt: nil)
        XCTAssertEqual(file.baseName, "photo.v2")
        XCTAssertEqual(file.fileExtension, "PNG")
        XCTAssertEqual(file.presentationKind, .thumbnail)
        XCTAssertEqual(file.fileName(withBaseName: "renamed"), "renamed.PNG")

        let noExtension = FileItem(url: URL(fileURLWithPath: "/tmp/README"), addedAt: nil, modifiedAt: nil)
        XCTAssertEqual(noExtension.baseName, "README")
        XCTAssertEqual(noExtension.fileName(withBaseName: "NOTES"), "NOTES")
    }

    private func createFile(named fileName: String, modifiedAt: Date) throws {
        let fileURL = temporaryDirectory.appendingPathComponent(fileName)
        try Data("test".utf8).write(to: fileURL)
        try FileManager.default.setAttributes(
            [.modificationDate: modifiedAt],
            ofItemAtPath: fileURL.path
        )
    }

    private func makeFileItem(named fileName: String, addedAt: Date? = nil) -> FileItem {
        FileItem(
            url: temporaryDirectory.appendingPathComponent(fileName),
            addedAt: addedAt,
            modifiedAt: nil
        )
    }
}
