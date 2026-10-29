import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import AppFolderKit

@Suite("Widget artwork cache")
struct WidgetArtworkCacheTests {
    @Test("Legacy artwork has independent preview and full-tile cache entries", arguments: [32, 256])
    func sizesRemainIndependent(firstSize: Int) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("123.png")
        let original = try legacyPNG()
        try original.write(to: file)
        let cache = WidgetArtworkCache(directory: directory)
        let secondSize = firstSize == 32 ? 256 : 32
        let first = try #require(cache.image(appStoreID: 123, maxPixelSize: firstSize))
        let second = try #require(cache.image(appStoreID: 123, maxPixelSize: secondSize))

        #expect(first.width == firstSize && first.height == firstSize)
        #expect(second.width == secondSize && second.height == secondSize)
        #expect(first !== second)
        #expect(try Data(contentsOf: file) == original, "rendering must not replace the legacy disk artwork")

        // Both sizes remain independent memory hits even without the disk file.
        try FileManager.default.removeItem(at: file)
        #expect(cache.image(appStoreID: 123, maxPixelSize: firstSize) === first)
        #expect(cache.image(appStoreID: 123, maxPixelSize: secondSize) === second)
    }

    @Test("A page of 36 folder miniatures retains small decoded pixels from 512-pixel files")
    func fullFolderPageStaysSmall() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try legacyPNG()
        for id in 1...36 { try original.write(to: directory.appendingPathComponent("\(id).png")) }
        let cache = WidgetArtworkCache(directory: directory)
        let images = try (1...36).map { id in
            try #require(cache.image(appStoreID: id, maxPixelSize: 32))
        }

        #expect(images.allSatisfy { $0.width == 32 && $0.height == 32 })
        let retainedPixelBytes = images.reduce(0) { $0 + $1.bytesPerRow * $1.height }
        #expect(retainedPixelBytes <= 256 * 1_024,
                "36 visible miniatures must not retain the roughly 36 MiB of their 512px sources")
    }

    @Test("Extreme render requests are bounded and an invalid source is not cached")
    func invalidAndExtremeInputs() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("123.png")
        let cache = WidgetArtworkCache(directory: directory)
        try Data("not an image".utf8).write(to: file)
        #expect(cache.image(appStoreID: 123, maxPixelSize: 32) == nil)

        let original = try legacyPNG()
        try original.write(to: file)
        let recovered = try #require(cache.image(appStoreID: 123, maxPixelSize: 32))
        let large = try #require(cache.image(appStoreID: 123, maxPixelSize: Int.max))
        let small = try #require(cache.image(appStoreID: 123, maxPixelSize: Int.min))
        #expect(recovered.width == 32)
        #expect(large.width == 256 && large.height == 256)
        #expect(small.width == 1 && small.height == 1)
        #expect(cache.image(appStoreID: 123, maxPixelSize: 256) === large)
        #expect(try Data(contentsOf: file) == original)
        #expect(cache.image(appStoreID: -1) == nil)
        #expect(WidgetArtworkCache(directory: nil).image(appStoreID: 123) == nil)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppFolder-widget-artwork-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func legacyPNG() throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: 512, height: 512, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.1, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
