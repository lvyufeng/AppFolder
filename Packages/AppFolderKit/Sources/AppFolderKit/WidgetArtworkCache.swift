import CoreGraphics
import Foundation

/// Decoded widget artwork bounded by both pixel size and entry count.
/// Reading a legacy image never rewrites the durable file. A folder preview and
/// a full tile keep separate cached images, so neither determines the other's
/// resolution or memory use.
public final class WidgetArtworkCache: @unchecked Sendable {
    private struct Key: Hashable {
        let filename: String
        let maxPixelSize: Int
    }

    private static let capacity = 32
    private let directory: URL?
    private let lock = NSLock()
    private var images: [Key: CGImage] = [:]
    private var recency: [Key] = []

    public init(directory: URL?) {
        self.directory = directory
    }

    /// The caller supplies a pixel ceiling, clamped to 1...256. Source bytes are
    /// validated and downsampled with ImageIO before any image enters the cache.
    public func image(appStoreID: Int, country: String? = nil, maxPixelSize: Int = 256) -> CGImage? {
        guard let filename = DirectLaunchIcons.fileName(appStoreID: appStoreID, country: country),
              let directory else { return nil }
        let key = Key(filename: filename,
                      maxPixelSize: min(max(1, maxPixelSize), DirectLaunchIcons.artworkPixelLimit))
        lock.lock()
        if let image = images[key] {
            touch(key)
            lock.unlock()
            return image
        }
        lock.unlock()

        let file = directory.appendingPathComponent(filename)
        let decoded: CGImage? = autoreleasepool {
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true, let size = values.fileSize,
                  size > 0, size <= DirectLaunchIcons.artworkByteLimit,
                  let data = try? Data(contentsOf: file) else { return nil }
            return DirectLaunchIcons.artworkThumbnail(data, maxPixelSize: key.maxPixelSize)
        }
        guard let decoded else { return nil }

        lock.lock()
        defer { lock.unlock() }
        // Concurrent readers of the same key share the first completed decode.
        if images[key] == nil { images[key] = decoded }
        touch(key)
        while recency.count > Self.capacity {
            images.removeValue(forKey: recency.removeFirst())
        }
        return images[key]
    }

    /// The caller holds the lock.
    private func touch(_ key: Key) {
        if let index = recency.firstIndex(of: key) { recency.remove(at: index) }
        recency.append(key)
    }
}
