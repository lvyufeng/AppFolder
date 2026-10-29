import CoreGraphics
import Foundation
import ImageIO

/// Site artwork is always decoded and redrawn as a small metadata-free PNG.
/// ICO directories may contain several sizes; only the best bounded entry is
/// decoded. Source image properties never enter a saved CustomIcon.
enum WebsiteMetadataArtwork {
    static let maximumBytes = 2 * 1_024 * 1_024
    static let maximumSide = 4_096
    static let maximumPixels = 4_000_000
    static let maximumICOEntries = 64

    static func decode(_ data: Data) throws -> CustomIcon? {
        try Task.checkCancellation()
        guard !data.isEmpty, data.count <= maximumBytes else { return nil }
        return try autoreleasepool {
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let type = CGImageSourceGetType(source) as String?,
                  ["public.png", "public.jpeg", "com.microsoft.ico"].contains(type),
                  CGImageSourceGetStatus(source) == .statusComplete else { return nil }
            let count = CGImageSourceGetCount(source)
            if type == "com.microsoft.ico" {
                guard validICO(data), (1...maximumICOEntries).contains(count) else { return nil }
            } else {
                guard count == 1 else { return nil }
                if type == "public.png" {
                    guard DirectLaunchIcons.hasCompleteImageContainer(data, type: type) else { return nil }
                } else {
                    guard data.starts(with: [0xFF, 0xD8]), data.suffix(2) == Data([0xFF, 0xD9]) else { return nil }
                }
            }
            var choices: [(index: Int, side: Int)] = []
            for index in 0..<count {
                guard CGImageSourceGetStatusAtIndex(source, index) == .statusComplete,
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                      let width = properties[kCGImagePropertyPixelWidth] as? Int,
                      let height = properties[kCGImagePropertyPixelHeight] as? Int,
                      width > 0, height > 0, width <= maximumSide, height <= maximumSide,
                      width <= maximumPixels / height else { continue }
                choices.append((index, max(width, height)))
            }
            // Prefer the smallest source at least as large as the output; when
            // all are smaller, choose the largest without upscaling it.
            choices.sort {
                let lhs = $0.side >= 256, rhs = $1.side >= 256
                if lhs != rhs { return lhs }
                return lhs ? $0.side < $1.side : $0.side > $1.side
            }
            for choice in choices {
                try Task.checkCancellation()
                guard let image = CGImageSourceCreateThumbnailAtIndex(source, choice.index, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: CustomIcon.maximumPhotoSide,
                    kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary), image.width > 0, image.height > 0,
                      image.width <= 256, image.height <= 256 else { continue }
                if let result = png(image) { return result }
            }
            return nil
        }
    }

    private static func png(_ image: CGImage) -> CustomIcon? {
        let side = max(image.width, image.height)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: side, height: side))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: CGFloat(side - image.width) / 2, y: CGFloat(side - image.height) / 2,
                                       width: CGFloat(image.width), height: CGFloat(image.height)))
        guard let pixels = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, pixels, nil)
        guard CGImageDestinationFinalize(destination), output.length <= CustomIcon.maximumPhotoBytes else { return nil }
        return CustomIcon.photo(pngData: output as Data, backgroundHex: "#FFFFFF")
    }

    private static func validICO(_ data: Data) -> Bool {
        let bytes = Array(data)
        guard bytes.count >= 6, bytes[0...3].elementsEqual([0, 0, 1, 0]) else { return false }
        func word16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        func word32(_ at: Int) -> UInt64 {
            UInt64(bytes[at]) | UInt64(bytes[at + 1]) << 8 | UInt64(bytes[at + 2]) << 16 | UInt64(bytes[at + 3]) << 24
        }
        let count = word16(4)
        guard (1...maximumICOEntries).contains(count), bytes.count >= 6 + count * 16 else { return false }
        for entry in 0..<count {
            let start = 6 + entry * 16
            let length = word32(start + 8), offset = word32(start + 12)
            guard length > 0, offset >= 6 + count * 16, offset <= bytes.count,
                  length <= UInt64(bytes.count) - offset else { return false }
        }
        return true
    }
}
