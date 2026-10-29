import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import AppFolderKit

@Suite("Storefront artwork identity")
struct DirectLaunchStorefrontArtworkTests {
    @Test("An explicit storefront uses its matching ID only and never falls back to another country")
    func explicitLookup() async throws {
        let png = try image(red: 1, green: 0, blue: 0)
        var requests: [URL] = []
        let fetched = await DirectLaunchIcons.fetch(appStoreID: 123, country: "JP") { url in
            requests.append(url)
            if url.host == "artwork.example" { return png }
            return Data(#"{"results":[{"trackId":999,"trackName":"Other","artworkUrl512":"https://wrong.example/icon.png"},{"trackId":123,"trackName":"Chosen","artworkUrl512":"https://artwork.example/jp.png"}]}"#.utf8)
        }
        #expect(fetched != nil)
        #expect(requests.count == 2)
        #expect(country(in: requests[0]) == "jp")
        #expect(requests[1].host == "artwork.example")

        for response in [Data(#"{"results":[]}"#.utf8), Data(#"{"results":[{"trackId":999,"trackName":"Other","artworkUrl512":"https://wrong.example/icon.png"}]}"#.utf8)] {
            requests = []
            let missing = await DirectLaunchIcons.fetch(appStoreID: 123, country: "jp") { url in
                requests.append(url)
                return response
            }
            #expect(missing == nil)
            #expect(requests.count == 1 && country(in: requests[0]) == "jp")
        }
    }

    @Test("Legacy, Japan and China artwork for one ID have separate disk and memory entries")
    func cacheIsolation() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = try image(red: 0, green: 0, blue: 1)
        let japan = try image(red: 1, green: 0, blue: 0)
        let china = try image(red: 0, green: 1, blue: 0)
        try legacy.write(to: directory.appendingPathComponent("123.png"))
        var observedCountries: [String?] = []
        for (region, bytes) in [("jp", japan), ("cn", china)] {
            let result = await DirectLaunchIcons.ensureIcon(appStoreID: 123, country: region, directory: directory) { url in
                if url.host == "artwork.example" { return bytes }
                observedCountries.append(country(in: url))
                return lookup
            }
            #expect(result != nil)
            #expect(DirectLaunchIcons.cachedIcon(appStoreID: 123, country: region, directory: directory) == result)
        }
        #expect(observedCountries == ["jp", "cn"])
        #expect(try Data(contentsOf: directory.appendingPathComponent("123.png")) == legacy)
        let cached = await DirectLaunchIcons.ensureIcon(appStoreID: 123, country: "JP", directory: directory) { _ in
            Issue.record("An existing Japan entry should not make a request")
            return nil
        }
        #expect(cached == DirectLaunchIcons.cachedIcon(appStoreID: 123, country: "jp", directory: directory))
        let memory = WidgetArtworkCache(directory: directory)
        let old = try #require(memory.image(appStoreID: 123, maxPixelSize: 32))
        let jp = try #require(memory.image(appStoreID: 123, country: "jp", maxPixelSize: 32))
        let cn = try #require(memory.image(appStoreID: 123, country: "cn", maxPixelSize: 32))
        #expect(old !== jp && jp !== cn && old !== cn)
        let oldPixel = try pixel(old)
        let japanPixel = try pixel(jp)
        let chinaPixel = try pixel(cn)
        #expect(oldPixel == [0, 0, 255, 255])
        #expect(japanPixel == [255, 0, 0, 255])
        #expect(chinaPixel == [0, 255, 0, 255])
        for name in ["123.png", "123-jp.png", "123-cn.png"] {
            try FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
        #expect(memory.image(appStoreID: 123, country: "JP", maxPixelSize: 32) === jp)
        #expect(memory.image(appStoreID: 123, country: "cn", maxPixelSize: 32) === cn)
        #expect(memory.image(appStoreID: 123, maxPixelSize: 32) === old)
    }

    @Test("Invalid country input makes no path or request and a failed explicit fetch does not touch legacy artwork")
    func invalidAndFailed() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = try image(red: 0, green: 0, blue: 1)
        try legacy.write(to: directory.appendingPathComponent("123.png"))
        for invalid in ["", "../cn", "cn/us", "us?other=jp", "zz", "aq"] {
            #expect(DirectLaunchIcons.fileName(appStoreID: 123, country: invalid) == nil)
            let result = await DirectLaunchIcons.ensureIcon(appStoreID: 123, country: invalid, directory: directory) { _ in
                Issue.record("Invalid countries must be rejected before transport")
                return nil
            }
            #expect(result == nil)
        }
        var count = 0
        let unavailable = await DirectLaunchIcons.ensureIcon(appStoreID: 123, country: "jp", directory: directory) { _ in
            count += 1
            return nil
        }
        #expect(count == 1 && unavailable == nil)
        #expect(DirectLaunchIcons.cachedIcon(appStoreID: 123, country: "jp", directory: directory) == nil)
        #expect(try Data(contentsOf: directory.appendingPathComponent("123.png")) == legacy)
        #expect(DirectLaunchIcons.fileName(appStoreID: 0, country: "jp") == nil)
    }

    @Test("Cancellation after metadata lookup prevents the artwork request and cache write")
    func cancellation() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let response = lookup
        let task = Task {
            await DirectLaunchIcons.ensureIcon(appStoreID: 123, country: "jp", directory: directory) { url in
                #expect(url.host == "itunes.apple.com")
                withUnsafeCurrentTask { $0?.cancel() }
                return response
            }
        }
        #expect(await task.value == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("123-jp.png").path))
    }

    private var lookup: Data {
        Data(#"{"results":[{"trackId":123,"trackName":"Chosen","artworkUrl512":"https://artwork.example/icon.png"}]}"#.utf8)
    }

    private func country(in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "country" }?.value
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("storefront-artwork-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func image(red: CGFloat, green: CGFloat, blue: CGFloat) throws -> Data {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let color = try #require(CGColor(colorSpace: colorSpace, components: [red, green, blue, 1]))
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func pixel(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: colorSpace, bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes
    }
}
