import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AppFolderKit

@Suite("Direct launch artwork")
struct DirectLaunchArtworkTests {
    private let appID = 123

    private var lookup: Data {
        Data(#"{"results":[{"trackId":123,"trackName":"Example","artworkUrl512":"https://artwork.example/icon.png"}]}"#.utf8)
    }

    @Test("Non-image HTTP bodies never become artwork", arguments: [
        Data(),
        Data("<html>Service unavailable</html>".utf8),
        Data(#"{"error":"temporarily unavailable"}"#.utf8),
        Data([137, 80, 78, 71, 13, 10, 26, 10]),
    ])
    func malformedArtworkIsRejected(_ data: Data) {
        #expect(DirectLaunchIcons.normalizedArtwork(data) == nil)
    }

    @Test("Truncated image data is not accepted as a cached icon")
    func incompleteImageIsRejected() throws {
        let complete = try png(width: 512, height: 512)
        #expect(DirectLaunchIcons.normalizedArtwork(Data(complete.prefix(complete.count / 2))) == nil)
    }

    @Test("A damaged PNG checksum cannot be silently cached as recovered pixels")
    func corruptedPNGIsRejected() throws {
        var damaged = try png(width: 256, height: 256)
        // The final IEND checksum is part of the PNG, even when its pixels decode.
        damaged[damaged.count - 1] ^= 1
        #expect(DirectLaunchIcons.normalizedArtwork(damaged) == nil)
    }

    @Test("New artwork is a decodable PNG bounded to 256 pixels")
    func largeArtworkIsDownsampled() throws {
        let original = try png(width: 512, height: 512)
        let normalized = try #require(DirectLaunchIcons.normalizedArtwork(original))
        let source = try #require(CGImageSourceCreateWithData(normalized as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))

        #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
        #expect(image.width == 256)
        #expect(image.height == 256)
        #expect(normalized.count < 512 * 1_024)
    }

    @Test("JPEG artwork is normalized, but a missing end marker is rejected")
    func jpegNormalizationAndTruncation() throws {
        let pngData = try png(width: 512, height: 512)
        let source = try #require(CGImageSourceCreateWithData(pngData as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let jpeg = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))

        let bytes = jpeg as Data
        let normalized = try #require(DirectLaunchIcons.normalizedArtwork(bytes))
        let normalizedSource = try #require(CGImageSourceCreateWithData(normalized as CFData, nil))
        #expect(CGImageSourceGetType(normalizedSource) as String? == UTType.png.identifier)
        #expect(DirectLaunchIcons.normalizedArtwork(Data(bytes.dropLast(2))) == nil)
    }

    @Test("Sources outside the decode bounds are refused")
    func oversizedSourcesAreRejected() throws {
        let tooWide = try png(width: DirectLaunchIcons.artworkSourceSideLimit + 1, height: 1)
        #expect(DirectLaunchIcons.normalizedArtwork(tooWide) == nil)
        #expect(DirectLaunchIcons.normalizedArtwork(
            Data(repeating: 0, count: DirectLaunchIcons.artworkByteLimit + 1)
        ) == nil)
    }

    @Test("A malformed HTTP image does not poison the cache and a later request recovers")
    func failedDownloadThenRecovery() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: DirectLaunchIcons.fileName(appStoreID: appID))
        var requests = 0
        let failed = await DirectLaunchIcons.ensureIcon(appStoreID: appID, directory: directory) { url in
            requests += 1
            return url.host == "artwork.example" ? Data("<html>HTTP 200 error</html>".utf8) : lookup
        }

        #expect(failed == nil)
        #expect(requests > 0)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(DirectLaunchIcons.cachedIcon(appStoreID: appID, directory: directory) == nil)

        let valid = try png(width: 512, height: 512)
        let recovered = try #require(await DirectLaunchIcons.ensureIcon(appStoreID: appID, directory: directory) { url in
            url.host == "artwork.example" ? valid : lookup
        })
        #expect(try Data(contentsOf: file) == recovered)
        #expect(DirectLaunchIcons.cachedIcon(appStoreID: appID, directory: directory) == recovered)

        var fetchedAgain = false
        let cached = await DirectLaunchIcons.ensureIcon(appStoreID: appID, directory: directory) { _ in
            fetchedAgain = true
            return nil
        }
        #expect(cached == recovered)
        #expect(!fetchedAgain, "a good cached icon remains available without networking")
    }

    @Test("A corrupt cache entry is a miss and can be replaced")
    func corruptCacheRecovers() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: DirectLaunchIcons.fileName(appStoreID: appID))
        try Data("not an image".utf8).write(to: file)
        #expect(DirectLaunchIcons.cachedIcon(appStoreID: appID, directory: directory) == nil)

        let valid = try png(width: 256, height: 256)
        let recovered = try #require(await DirectLaunchIcons.ensureIcon(appStoreID: appID, directory: directory) { url in
            url.host == "artwork.example" ? valid : lookup
        })
        #expect(try Data(contentsOf: file) == recovered)
        #expect(DirectLaunchIcons.cachedIcon(appStoreID: appID, directory: directory) == recovered)
    }

    @Test("Existing valid 512-pixel artwork remains readable offline")
    func legacyArtworkRemainsReadable() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: DirectLaunchIcons.fileName(appStoreID: appID))
        let legacy = try png(width: 512, height: 512)
        try legacy.write(to: file)

        var madeRequest = false
        let cached = await DirectLaunchIcons.ensureIcon(appStoreID: appID, directory: directory) { _ in
            madeRequest = true
            return nil
        }
        #expect(cached == legacy)
        #expect(!madeRequest)
        #expect(try Data(contentsOf: file) == legacy)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "AppFolder-artwork-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Real image fixtures exercise the decoder rather than trusting a file suffix.
    private func png(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.1, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
