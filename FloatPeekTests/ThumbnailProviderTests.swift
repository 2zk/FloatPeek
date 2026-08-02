import XCTest
@testable import FloatPeek

@MainActor
final class ThumbnailProviderTests: XCTestCase {
    func testFileIconFallsBackForUnknownExtension() {
        let icon = ThumbnailProvider.shared.fileIcon(
            forFileExtension: ""
        )

        XCTAssertFalse(icon.representations.isEmpty)
    }

    func testAspectFitSizePreservesWideImageAspectRatio() throws {
        let sourceSize = CGSize(width: 769, height: 59)

        let fittedSize = try XCTUnwrap(
            ThumbnailProvider.aspectFitSize(
                sourceSize: sourceSize,
                boundingSize: CGSize(width: 120, height: 96)
            )
        )

        XCTAssertEqual(fittedSize.width, 120, accuracy: 0.001)
        XCTAssertEqual(fittedSize.height, 59 * 120 / 769, accuracy: 0.001)
        XCTAssertEqual(
            fittedSize.width / fittedSize.height,
            sourceSize.width / sourceSize.height,
            accuracy: 0.001
        )
    }

    func testAspectFitSizePreservesTallImageAspectRatio() throws {
        let sourceSize = CGSize(width: 59, height: 769)

        let fittedSize = try XCTUnwrap(
            ThumbnailProvider.aspectFitSize(
                sourceSize: sourceSize,
                boundingSize: CGSize(width: 120, height: 96)
            )
        )

        XCTAssertEqual(fittedSize.width, 59 * 96 / 769, accuracy: 0.001)
        XCTAssertEqual(fittedSize.height, 96, accuracy: 0.001)
        XCTAssertEqual(
            fittedSize.width / fittedSize.height,
            sourceSize.width / sourceSize.height,
            accuracy: 0.001
        )
    }
}
