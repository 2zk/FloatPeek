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

    func testFallbackDownsamplesBitmapImageToBoundingSize() throws {
        let fileURL = try makePNG(width: 800, height: 400)

        let image = try XCTUnwrap(
            ThumbnailProvider.loadImageFallback(
                fileURL: fileURL,
                size: CGSize(width: 120, height: 96),
                scale: 2
            )
        )

        XCTAssertEqual(image.size.width, 120, accuracy: 0.001)
        XCTAssertEqual(image.size.height, 60, accuracy: 0.001)
        let pixelWidth = try XCTUnwrap(image.representations.first?.pixelsWide)
        XCTAssertLessThanOrEqual(pixelWidth, 240)
    }

    func testFallbackRendersVectorImageNotSupportedByImageIO() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).svg")
        try """
        <svg xmlns="http://www.w3.org/2000/svg" width="200" height="100">
        <rect width="200" height="100" fill="red"/></svg>
        """.write(to: fileURL, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: fileURL) }

        let image = try XCTUnwrap(
            ThumbnailProvider.loadImageFallback(
                fileURL: fileURL,
                size: CGSize(width: 120, height: 96),
                scale: 2
            )
        )

        XCTAssertEqual(image.size.width, 120, accuracy: 0.001)
        XCTAssertEqual(image.size.height, 60, accuracy: 0.001)
    }

    private func makePNG(width: Int, height: Int) throws -> URL {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).png")
        try data.write(to: fileURL)
        addTeardownBlock { try? FileManager.default.removeItem(at: fileURL) }
        return fileURL
    }
}
