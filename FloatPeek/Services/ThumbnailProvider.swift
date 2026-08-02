import AppKit
import Foundation
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

            guard let fallbackImage = loadImageFallback(fileURL: imageFile.url, size: size) else {
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

    private nonisolated func loadImageFallback(fileURL: URL, size: CGSize) -> NSImage? {
        guard let sourceImage = NSImage(contentsOf: fileURL) else {
            return nil
        }

        let sourceSize = sourceImage.size
        guard let fittedSize = Self.aspectFitSize(
            sourceSize: sourceSize,
            boundingSize: size
        ) else {
            return nil
        }

        let targetImage = NSImage(size: fittedSize)
        targetImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        sourceImage.draw(in: CGRect(origin: .zero, size: fittedSize))
        targetImage.unlockFocus()
        return targetImage
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
