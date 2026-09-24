import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
@preconcurrency import QuickLookThumbnailing

@MainActor
final class ThumbnailProvider {
    static let shared = ThumbnailProvider()

    private let cache = NSCache<NSString, NSImage>()
    private let fileIconCache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 512
        cache.totalCostLimit = 64 * 1_024 * 1_024
    }

    func thumbnail(for imageFile: ImageFile, size: CGSize) async -> NSImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let cacheKey = cacheKey(for: imageFile, size: size, scale: scale)

        if let cachedImage = cache.object(forKey: cacheKey) {
            return cachedImage
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: imageFile.url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )

        do {
            let image = try await generateThumbnail(for: request)
            cache(image, forKey: cacheKey, size: size, scale: scale)
            return image
        } catch {
            guard !Task.isCancelled else {
                return nil
            }

            let fileURL = imageFile.url
            // フォールバックは画像全体の読み込みを伴うため、メインスレッド外で実行する
            let fallbackImage = await Task.detached(priority: .utility) {
                Self.loadImageFallback(fileURL: fileURL, size: size, scale: scale)
            }.value
            guard let fallbackImage, !Task.isCancelled else {
                return nil
            }

            cache(fallbackImage, forKey: cacheKey, size: size, scale: scale)
            return fallbackImage
        }
    }

    func clearCache() {
        cache.removeAllObjects()
        fileIconCache.removeAllObjects()
    }

    func fileIcon(forFileExtension fileExtension: String) -> NSImage {
        let normalizedExtension = fileExtension.lowercased()
        let cacheKey = (normalizedExtension.isEmpty ? "unknown" : normalizedExtension) as NSString
        if let cachedIcon = fileIconCache.object(forKey: cacheKey) {
            return cachedIcon
        }

        let icon = UTType(filenameExtension: normalizedExtension).map {
            NSWorkspace.shared.icon(for: $0)
        } ?? NSWorkspace.shared.icon(for: .data)
        fileIconCache.setObject(icon, forKey: cacheKey)
        return icon
    }

    private func cacheKey(
        for imageFile: ImageFile,
        size: CGSize,
        scale: CGFloat
    ) -> NSString {
        let modifiedAt = imageFile.modifiedAt.map {
            String($0.timeIntervalSinceReferenceDate.bitPattern)
        } ?? "nil"
        return "\(imageFile.url.standardizedFileURL.path)|\(modifiedAt)|\(Double(size.width).bitPattern)|\(Double(size.height).bitPattern)|\(Double(scale).bitPattern)" as NSString
    }

    private func cache(
        _ image: NSImage,
        forKey cacheKey: NSString,
        size: CGSize,
        scale: CGFloat
    ) {
        let pixelWidth = max(Int(ceil(size.width * scale)), 1)
        let pixelHeight = max(Int(ceil(size.height * scale)), 1)
        cache.setObject(
            image,
            forKey: cacheKey,
            cost: pixelWidth * pixelHeight * 4
        )
    }

    private nonisolated func generateThumbnail(
        for request: QLThumbnailGenerator.Request
    ) async throws -> NSImage {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let representation else {
                        continuation.resume(throwing: ThumbnailProviderError.noRepresentation)
                        return
                    }

                    continuation.resume(returning: representation.nsImage)
                }
            }
        } onCancel: {
            QLThumbnailGenerator.shared.cancel(request)
        }
    }

    nonisolated static func loadImageFallback(
        fileURL: URL,
        size: CGSize,
        scale: CGFloat
    ) -> NSImage? {
        downsampledImage(fileURL: fileURL, size: size, scale: scale)
            ?? renderedImage(fileURL: fileURL, size: size, scale: scale)
    }

    /// ImageIO で扱える形式は、元画像全体をデコードせずに縮小画像を生成する
    private nonisolated static func downsampledImage(
        fileURL: URL,
        size: CGSize,
        scale: CGFloat
    ) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return nil
        }

        let maxPixelSize = max(size.width, size.height) * scale
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(Int(ceil(maxPixelSize)), 1)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ), let fittedSize = aspectFitSize(
            sourceSize: CGSize(width: cgImage.width, height: cgImage.height),
            boundingSize: size
        ) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: fittedSize)
    }

    /// SVG や PDF など ImageIO で扱えない形式は NSImage で読み込み、ビットマップへ描画する
    private nonisolated static func renderedImage(
        fileURL: URL,
        size: CGSize,
        scale: CGFloat
    ) -> NSImage? {
        guard let sourceImage = NSImage(contentsOf: fileURL),
              let fittedSize = aspectFitSize(
                sourceSize: sourceImage.size,
                boundingSize: size
              ),
              let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: max(Int(ceil(fittedSize.width * scale)), 1),
                pixelsHigh: max(Int(ceil(fittedSize.height * scale)), 1),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              ),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }

        bitmap.size = fittedSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        sourceImage.draw(in: CGRect(origin: .zero, size: fittedSize))
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: fittedSize)
        image.addRepresentation(bitmap)
        return image
    }

    nonisolated static func aspectFitSize(
        sourceSize: CGSize,
        boundingSize: CGSize
    ) -> CGSize? {
        guard sourceSize.width > 0,
              sourceSize.height > 0,
              boundingSize.width > 0,
              boundingSize.height > 0 else {
            return nil
        }

        let scale = min(
            boundingSize.width / sourceSize.width,
            boundingSize.height / sourceSize.height
        )
        return CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )
    }
}

private enum ThumbnailProviderError: Error {
    case noRepresentation
}
