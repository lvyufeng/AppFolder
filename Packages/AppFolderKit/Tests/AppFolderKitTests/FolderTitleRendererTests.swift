import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import AppFolderKit

@Suite("Bounded folder title rendering")
struct FolderTitleRendererTests {
    private let white = FolderTitleRGBA(red: 1, green: 1, blue: 1, alpha: 1)
    private let blue = FolderTitleRGBA(red: 0, green: 0, blue: 1, alpha: 1)

    private func request(_ text: String = "Folder", width: CGFloat = 100, fontSize: CGFloat = 14,
                         height: CGFloat? = nil, scale: CGFloat = 3,
                         outlineWidth: CGFloat = 1, outlined: Bool = true,
                         foreground: FolderTitleRGBA? = nil) -> FolderTitleRenderRequest {
        .init(text: text, fontSize: fontSize, width: width, availableHeight: height,
              minimumScaleFactor: 0.7, weight: 0, displayScale: scale,
              foreground: foreground ?? white, outline: outlined ? blue : nil,
              outlineWidth: outlineWidth)
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: image.width, height: image.height,
                                             bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                             space: colorSpace,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try #require(context.data)
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self),
                                         count: image.width * image.height * 4))
    }

    @Test("A glyph has independent fill and actual outline pixels without a blurred halo")
    func genuineStroke() throws {
        let plain = try #require(FolderTitleRenderer.render(request("H", outlined: false)))
        let outlined = try #require(FolderTitleRenderer.render(request("H", outlineWidth: 1.5)))
        let plainPixels = try pixels(plain.image)
        let outlinePixels = try pixels(outlined.image)
        var bluePixels = 0, whitePixels = 0
        for index in stride(from: 0, to: outlinePixels.count, by: 4) where outlinePixels[index + 3] > 180 {
            if Int(outlinePixels[index + 2]) > Int(outlinePixels[index]) + 30 { bluePixels += 1 }
            if outlinePixels[index] > 180 && outlinePixels[index + 1] > 180 { whitePixels += 1 }
        }
        #expect(bluePixels > 10)
        #expect(whitePixels > 10)
        #expect(plainPixels != outlinePixels)
        try emitSample(plain.image, name: "plain")
        try emitSample(outlined.image, name: "outlined-thick")
        // Ample horizontal room around one centered glyph stays fully clear.
        for row in 0..<outlined.image.height {
            #expect(outlinePixels[(row * outlined.image.width) * 4 + 3] == 0)
            #expect(outlinePixels[(row * outlined.image.width + outlined.image.width - 1) * 4 + 3] == 0)
        }
    }

    @Test("Long mixed names shrink to the allowed floor then receive a fitted ellipsis")
    func longNameTruncates() throws {
        let title = "工作资料 Research and shared documents 重要文件"
        let image = try #require(FolderTitleRenderer.render(request(title, width: 42)))
        #expect(image.isTruncated)
        #expect(abs(image.fittedFontSize - 9.8) < 0.001)
        #expect(image.lineWidth <= 40.01)
        #expect(try pixels(image.image).contains { $0 != 0 })
        try emitSample(image.image, name: "truncated-mixed")
        let short = try #require(FolderTitleRenderer.render(request("工作", width: 100)))
        #expect(!short.isTruncated)
        #expect(short.fittedFontSize == 14)
    }

    @Test("Arabic, combining marks, CJK and color emoji retain visible shaped output", arguments: [
        "مرحبا بالعالم", "Cafe\u{301} 中文", "🍎 工作", "עברית 123"
    ])
    func multilingual(_ title: String) throws {
        let rendered = try #require(FolderTitleRenderer.render(request(title, width: 120)))
        #expect(rendered.lineWidth > 0)
        #expect(try pixels(rendered.image).contains { $0 != 0 })
        #expect(rendered.image.width * rendered.image.height <= FolderTitleRenderer.maximumPixels)
        let sampleName = title == "مرحبا بالعالم" ? "arabic" : title == "עברית 123" ? "hebrew" : "mixed-\(title.utf8.count)"
        try emitSample(rendered.image, name: sampleName)
    }

    @Test("Color bitmap emoji are retained instead of disappearing in a glyph-path conversion")
    func colorEmojiSurvives() throws {
        let rendered = try #require(FolderTitleRenderer.render(request("🍎", width: 40, fontSize: 22)))
        let data = try pixels(rendered.image)
        var redPixels = 0
        for index in stride(from: 0, to: data.count, by: 4) {
            let red = Int(data[index]), green = Int(data[index + 1]), blue = Int(data[index + 2])
            if data[index + 3] > 100 && red > blue + 30 && red > green + 30 { redPixels += 1 }
        }
        #expect(redPixels > 10)
        try emitSample(rendered.image, name: "color-emoji")
    }

    @Test("Invalid or unrenderable dimensions reject allocation so the view can preserve native Text")
    func rejectsUnsafeDimensions() {
        for width: CGFloat in [0, -1, .nan, .infinity, 2_049] {
            #expect(FolderTitleRenderer.render(request(width: width)) == nil)
        }
        for height: CGFloat in [0, -1, .nan, .infinity, 513] {
            #expect(FolderTitleRenderer.render(request(height: height)) == nil)
        }
        #expect(FolderTitleRenderer.render(request("\n")) == nil)
        #expect(FolderTitleRenderer.render(request(String(repeating: "a", count: 81))) == nil)
        #expect(FolderTitleRenderer.render(request(width: 0.5)) == nil)
        #expect(FolderTitleRenderer.render(request(height: 0.5)) == nil)
    }

    @Test("Every accepted raster has bounded pixels and decoded byte cost", arguments: [1.0, 2.0, 3.0, 20.0])
    func boundedAllocation(_ scale: CGFloat) throws {
        let image = try #require(FolderTitleRenderer.render(request("Wide title", width: 2_048,
                                                                     fontSize: 128, scale: scale)))
        #expect(image.image.width <= 256)
        #expect(image.image.height <= 64)
        #expect(image.image.width * image.image.height <= 8_192)
        #expect(image.byteCost <= 32_768)
    }

    @Test("Small fixed-height cells keep glyphs and stroke inside the supplied title budget")
    func fixedHeightBudget() throws {
        let image = try #require(FolderTitleRenderer.render(request("工作文件", width: 45, fontSize: 10,
                                                                     height: 12, outlineWidth: 1.5)))
        #expect(image.size.height == 12)
        #expect(image.fittedFontSize >= 7)
        #expect(image.lineWidth <= 42.5)
    }

    @Test("Changed resolved colors and stroke widths do not reuse stale cached pixels")
    func independentCacheKeys() throws {
        let cache = FolderTitleRasterCache()
        let firstRequest = request("Cache")
        let first = try #require(cache.raster(for: firstRequest))
        let repeated = try #require(cache.raster(for: firstRequest))
        #expect(first.image === repeated.image)
        let changed = try #require(cache.raster(for: request("Cache", foreground: blue)))
        #expect(try pixels(first.image) != pixels(changed.image))
        let thinner = try #require(cache.raster(for: request("Cache", outlineWidth: 0.5)))
        #expect(try pixels(first.image) != pixels(thinner.image))
        #expect(cache.retainedCount == 3)
    }

    @Test("A complete 77-cell page and successive pages stay within raster and cache budgets")
    func densePageMemory() throws {
        let cache = FolderTitleRasterCache()
        var page: [FolderTitleRaster] = []
        for index in 0..<77 {
            page.append(try #require(cache.raster(for: request("项目 \(index)", width: 46, fontSize: 10,
                                                               height: 12, outlineWidth: 1.5))))
        }
        let visibleBytes = page.reduce(0) { $0 + $1.byteCost }
        #expect(visibleBytes <= 77 * 32_768)
        for index in 77..<231 {
            _ = try #require(cache.raster(for: request("项目 \(index)", width: 46, fontSize: 10,
                                                      height: 12, outlineWidth: 1.5)))
        }
        #expect(cache.retainedCost <= FolderTitleRasterCache.maximumCost)
        #expect(cache.retainedCount <= FolderTitleRasterCache.maximumEntries)
        print("FolderTitle 77-cell decoded bytes: \(visibleBytes); cache after 3 pages: \(cache.retainedCost) bytes / \(cache.retainedCount) entries")
    }

    private func emitSample(_ image: CGImage, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["APPFOLDER_TITLE_VALIDATION_DIRECTORY"] else { return }
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(name + ".png")
        let destination = try #require(CGImageDestinationCreateWithURL(target as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
