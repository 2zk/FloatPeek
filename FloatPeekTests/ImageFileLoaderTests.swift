import XCTest
@testable import FloatPeek

final class ImageFileLoaderTests: XCTestCase {
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

    func testLoadImagesFiltersSupportedExtensionsCaseInsensitively() throws {
        try createFile(named: "a.JPG", modifiedAt: Date(timeIntervalSince1970: 10))
        try createFile(named: "b.png", modifiedAt: Date(timeIntervalSince1970: 20))
        try createFile(named: "c.PDF", modifiedAt: Date(timeIntervalSince1970: 30))
        try createFile(named: "c.txt", modifiedAt: Date(timeIntervalSince1970: 30))

        let images = try ImageFileLoader().loadImages(in: temporaryDirectory, sortedBy: .modifiedAt)

        XCTAssertEqual(images.map(\.fileName), ["c.PDF", "b.png", "a.JPG"])
    }

    func testLoadImagesSortsByModifiedDateDescendingThenNameAscending() throws {
        let newerDate = Date(timeIntervalSince1970: 20)
        let olderDate = Date(timeIntervalSince1970: 10)
        try createFile(named: "z.png", modifiedAt: olderDate)
        try createFile(named: "b.png", modifiedAt: newerDate)
        try createFile(named: "a.png", modifiedAt: newerDate)

        let images = try ImageFileLoader().loadImages(in: temporaryDirectory, sortedBy: .modifiedAt)

        XCTAssertEqual(images.map(\.fileName), ["a.png", "b.png", "z.png"])
    }

    func testSortsByAddedDateDescendingThenNameAscending() {
        let newerDate = Date(timeIntervalSince1970: 20)
        let olderDate = Date(timeIntervalSince1970: 10)
        let images = [
            makeImageFile(named: "z.png", addedAt: olderDate),
            makeImageFile(named: "b.png", addedAt: newerDate),
            makeImageFile(named: "a.png", addedAt: newerDate)
        ]
        .sorted { lhs, rhs in
            ImageFileLoader.sort(lhs, rhs, by: .addedAt)
        }

        XCTAssertEqual(images.map(\.fileName), ["a.png", "b.png", "z.png"])
    }

    func testLoadImagesSortsByFileNameAscending() throws {
        try createFile(named: "z.png", modifiedAt: Date(timeIntervalSince1970: 30))
        try createFile(named: "a.png", modifiedAt: Date(timeIntervalSince1970: 20))
        try createFile(named: "c.PDF", modifiedAt: Date(timeIntervalSince1970: 10))

        let images = try ImageFileLoader().loadImages(in: temporaryDirectory, sortedBy: .fileName)

        XCTAssertEqual(images.map(\.fileName), ["a.png", "c.PDF", "z.png"])
    }

    func testLoadImagesThrowsForMissingFolder() {
        let missingFolder = temporaryDirectory.appendingPathComponent("missing", isDirectory: true)

        XCTAssertThrowsError(try ImageFileLoader().loadImages(in: missingFolder)) { error in
            XCTAssertEqual(error as? ImageFileLoaderError, .folderNotAccessible)
        }
    }

    private func createFile(named fileName: String, modifiedAt: Date) throws {
        let fileURL = temporaryDirectory.appendingPathComponent(fileName)
        try Data("test".utf8).write(to: fileURL)
        try FileManager.default.setAttributes(
            [.modificationDate: modifiedAt],
            ofItemAtPath: fileURL.path
        )
    }

    private func makeImageFile(named fileName: String, addedAt: Date?) -> ImageFile {
        ImageFile(
            url: temporaryDirectory.appendingPathComponent(fileName),
            addedAt: addedAt,
            modifiedAt: nil
        )
    }
}
