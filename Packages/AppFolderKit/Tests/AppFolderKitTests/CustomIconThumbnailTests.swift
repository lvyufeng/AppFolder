import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import AppFolderKit

@Suite("Custom icon folder thumbnails")
struct CustomIconThumbnailTests {
    @Test("Seventy-seven distinct two-appearance photo tiles retain under six MiB of decoded pixels")
    func portraitPhotoBudget() throws {
        let limit = WidgetArtworkResolution.maximumPixelSize(cellCount: 77)
        var retained: [CustomIconVariants] = []
        var pixels: [CGImage] = []
        for index in 0..<77 {
            try autoreleasepool {
                let standard = try noisyIcon(seed: UInt64(index * 2 + 2_000))
                let dark = try noisyIcon(seed: UInt64(index * 2 + 2_001))
                let source = CustomIconVariants(standard: standard, dark: dark)
                let tile = try #require(source.thumbnail(maxSide: limit))
                #expect(tile.standard?.pngData != tile.dark?.pngData)
                for icon in [tile.standard, tile.dark] {
                    let image = try #require(icon?.decodedPhoto(maxSide: limit))
                    #expect(image.width >= 96 && image.width <= limit)
                    pixels.append(image)
                }
                retained.append(tile)
                #expect(source.standard == standard && source.dark == dark)
            }
        }
        #expect(pixels.count == 154)
        #expect(pixels.reduce(0) { $0 + $1.bytesPerRow * $1.height } < 6 * 1_024 * 1_024)
        let compressedBytes = retained.reduce(0) {
            $0 + ($1.standard?.pngData?.count ?? 0) + ($1.dark?.pngData?.count ?? 0)
        }
        #expect(compressedBytes < 7 * 1_024 * 1_024)
    }

    @Test("Transparent photo thumbnails preserve their background color and source bytes")
    func transparentPhotoBackground() throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8,
                                             bytesPerRow: 256, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.clear(CGRect(x: 0, y: 0, width: 64, height: 64))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 16, y: 16, width: 32, height: 32))
        let pixels = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, pixels, nil)
        #expect(CGImageDestinationFinalize(destination))
        let originalBytes = data as Data
        let original = try #require(CustomIcon.photo(pngData: originalBytes, backgroundHex: "#A020F0"))
        let thumbnail = try #require(original.thumbnail(maxSide: 32))
        #expect(thumbnail.backgroundHex == original.backgroundHex)
        #expect(thumbnail.backgroundHex == "#A020F0")
        let image = try #require(thumbnail.decodedPhoto(maxSide: 32))
        #expect(image.width == 32 && image.height == 32)
        let check = try #require(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8,
                                           bytesPerRow: 128, space: space,
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        check.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        let bytes = try #require(check.data).assumingMemoryBound(to: UInt8.self)
        #expect(bytes[3] == 0, "the transparent corner still reveals the retained background")
        #expect(bytes[(16 * 32 + 16) * 4 + 3] == 255)
        #expect(original.pngData == originalBytes)
        #expect(CustomIcon.photo(pngData: originalBytes)?.backgroundHex == "#0A84FF")
        #expect(CustomIcon.photo(pngData: originalBytes, backgroundHex: "invalid") == nil)
    }

    @Test("One full photo plus sixty folder miniatures retain only their requested pixels")
    func sharedFullAndMiniPhoto() throws {
        let original = try noisyIcon(seed: 303, withMetadata: true)
        let sourceData = try #require(original.pngData)
        let full = try #require(original.decodedPhoto(maxSide: 256))
        #expect(full.width == 256 && full.height == 256)
        let miniatures = try (0..<60).map { _ in try #require(original.decodedPhoto(maxSide: 32)) }
        #expect(miniatures.allSatisfy { $0.width == 32 && $0.height == 32 })
        let retainedPixelBytes = full.bytesPerRow * full.height
            + miniatures.reduce(0) { $0 + $1.bytesPerRow * $1.height }
        #expect(retainedPixelBytes < 1_024 * 1_024)
        // Reversing the requested size must not reuse a prior miniature for a full tile.
        let fullAgain = try #require(original.decodedPhoto(maxSide: 256))
        #expect(fullAgain.width == 256 && fullAgain.height == 256)
        #expect(original.pngData == sourceData)
    }

    @Test("Pixel decode clamps extreme limits and ignores non-photo artwork")
    func pixelDecodeBounds() throws {
        let original = try noisyIcon(seed: 404)
        let sourceData = original.pngData
        for (requested, expected) in [(Int.min, 1), (0, 1), (32, 32), (Int.max, 256)] {
            let image = try #require(original.decodedPhoto(maxSide: requested))
            #expect(image.width == expected && image.height == expected)
        }
        let symbol = try #require(CustomIcon.symbol("moon.fill"))
        let emoji = try #require(CustomIcon.emoji("AB"))
        #expect(symbol.decodedPhoto() == nil)
        #expect(emoji.decodedPhoto() == nil)
        #expect(original.pngData == sourceData)
        // Malformed PNG bytes cannot enter the immutable photo value that renders.
        #expect(CustomIcon.photo(pngData: Data("invalid PNG".utf8)) == nil)
    }

    @Test("Both photo appearances shrink independently and absent variants stay absent")
    func appearanceThumbnails() throws {
        let standard = try noisyIcon(seed: 101)
        let dark = try noisyIcon(seed: 202)
        let pair = CustomIconVariants(standard: standard, dark: dark)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoVariants-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = CustomIconRepository(directory: directory)
        #expect(repository.setVariants(pair, name: "Two photos"))
        let preview = try #require(pair.thumbnail(maxSide: 32))
        #expect(preview.containsPhoto)
        #expect(preview.standard?.pngData != preview.dark?.pngData)
        for icon in [preview.standard, preview.dark] {
            let bytes = try #require(icon?.pngData)
            let source = try #require(CGImageSourceCreateWithData(bytes as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width == 32 && image.height == 32)
            #expect(bytes.count <= 8_192)
        }
        #expect(pair.standard == standard && pair.dark == dark)
        let reopened = CustomIconRepository(directory: directory)
        #expect(reopened.variants(name: "Two photos") == pair)
        #expect(reopened.variants(name: "Two photos")?.standard?.pngData == standard.pngData)
        #expect(reopened.variants(name: "Two photos")?.dark?.pngData == dark.pngData)
        let standardOnly = try #require(CustomIconVariants(standard: standard).thumbnail())
        #expect(standardOnly.standard != nil && standardOnly.dark == nil)
        #expect(standardOnly.resolved(isDark: true) == standardOnly.standard)
        let darkOnly = try #require(CustomIconVariants(dark: dark).thumbnail())
        #expect(darkOnly.standard == nil && darkOnly.dark != nil)
        #expect(darkOnly.resolved(isDark: false) == nil)
    }

    @Test("Symbol and emoji artwork remains unchanged")
    func nonPhotoArtwork() throws {
        let symbol = try #require(CustomIcon.symbol("heart.fill", backgroundHex: "#FF0000"))
        let emoji = try #require(CustomIcon.emoji("🐱"))
        #expect(symbol.thumbnail() == symbol)
        #expect(emoji.thumbnail() == emoji)
    }

    @Test("Photos become bounded PNGs without carrying source metadata")
    func photoDimensionsAndMetadata() throws {
        let original = try noisyIcon(seed: 7, withMetadata: true)
        let originalBytes = try #require(original.pngData)
        let originalSource = try #require(CGImageSourceCreateWithData(originalBytes as CFData, nil))
        let originalProperties = try #require(CGImageSourceCopyPropertiesAtIndex(originalSource, 0, nil) as? [CFString: Any])
        let sourcePNG = try #require(originalProperties[kCGImagePropertyPNGDictionary] as? [CFString: Any])
        #expect(sourcePNG[kCGImagePropertyPNGAuthor] as? String == "Private test author")

        let thumbnail = try #require(original.thumbnail())
        let bytes = try #require(thumbnail.pngData)
        let source = try #require(CGImageSourceCreateWithData(bytes as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 32)
        #expect(image.height == 32)
        #expect(bytes.count <= 8_192)
        #expect(thumbnail.isValid)
        #expect(original.pngData == originalBytes, "generating a preview never rewrites the saved photo")
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any]
        #expect(png?[kCGImagePropertyPNGAuthor] == nil)
        #expect(png?[kCGImagePropertyPNGDescription] == nil)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        // ImageIO may report generated color/dimension fields for the new PNG;
        // these describe only the rendered pixels, never the source photo.
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let generatedFields: Set<CFString> = [
            kCGImagePropertyExifColorSpace,
            kCGImagePropertyExifPixelXDimension,
            kCGImagePropertyExifPixelYDimension,
        ]
        #expect(Set(exif.keys).isSubset(of: generatedFields))
    }

    @Test("Extreme thumbnail sizes clamp to supported photo dimensions")
    func sizeClamping() throws {
        let original = try noisyIcon(seed: 11)
        for (requested, expected) in [(Int.min, 1), (0, 1), (16, 16), (Int.max, 256)] {
            let result = try #require(original.thumbnail(maxSide: requested))
            let bytes = try #require(result.pngData)
            let source = try #require(CGImageSourceCreateWithData(bytes as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width == expected)
            #expect(image.height == expected)
        }
    }

    @Test("Thirty-six distinct noisy folder previews retain under 288 KiB of image data")
    func fullFolderGridMemoryBound() throws {
        var retained: [CustomIcon] = []
        var originalBytes = 0
        for seed in 1...36 {
            let original = try noisyIcon(seed: UInt64(seed))
            originalBytes += try #require(original.pngData).count
            retained.append(try #require(original.thumbnail()))
        }
        let retainedBytes = retained.compactMap(\.pngData).reduce(0) { $0 + $1.count }
        #expect(Set(retained.compactMap(\.pngData)).count == 36)
        #expect(originalBytes > 6 * 1_024 * 1_024, "the fixture must represent large, distinct imported photos")
        #expect(retainedBytes <= 36 * 8_192)
        #expect(retainedBytes < originalBytes / 20)
    }

    private func noisyIcon(seed: UInt64, withMetadata: Bool = false) throws -> CustomIcon {
        let side = 256
        var state = seed
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        for pixel in 0..<(side * side) {
            for channel in 0..<3 {
                state ^= state << 13
                state ^= state >> 7
                state ^= state << 17
                pixels[pixel * 4 + channel] = UInt8(truncatingIfNeeded: state)
            }
        }
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let image = try #require(CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: side * 4, space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        ))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        let properties: [CFString: Any] = withMetadata ? [
            kCGImagePropertyPNGDictionary: [
                kCGImagePropertyPNGAuthor: "Private test author",
                kCGImagePropertyPNGDescription: "Private test description",
            ],
        ] : [:]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        let finalized = CGImageDestinationFinalize(destination)
        #expect(finalized)
        return try #require(CustomIcon.photo(pngData: data as Data))
    }
}
