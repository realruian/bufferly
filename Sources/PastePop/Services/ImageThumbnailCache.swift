import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 卡片墙只需要小图：用 ImageIO 直接从磁盘降采样，避免解码并长期持有原始分辨率图片。
actor ImageThumbnailCache {
    static let shared = ImageThumbnailCache()

    private let cache = NSCache<NSString, NSData>()

    private init() {
        cache.countLimit = 24
        cache.totalCostLimit = 8 * 1_024 * 1_024
    }

    func data(for filename: String) async -> Data? {
        let key = filename as NSString
        if let cached = cache.object(forKey: key) {
            return cached as Data
        }

        guard let fileURL = ClipBlobStore.url(for: filename) else {
            return nil
        }

        let thumbnail = await Task.detached(priority: .utility) {
            Self.makeThumbnailData(from: fileURL)
        }.value

        guard let thumbnail, !Task.isCancelled else {
            return nil
        }

        cache.setObject(thumbnail as NSData, forKey: key, cost: thumbnail.count)
        return thumbnail
    }

    private nonisolated static func makeThumbnailData(from fileURL: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            return nil
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
