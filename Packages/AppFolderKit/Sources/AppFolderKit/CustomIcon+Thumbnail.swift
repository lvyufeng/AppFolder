import CoreGraphics
import Foundation
import ImageIO

extension CustomIcon {
    /// Decodes only the requested pixels, even when the same photo is also used
    /// in a full-size tile. Source data remains unchanged and is never upscaled.
    public func decodedPhoto(maxSide: Int = 256) -> CGImage? {
        guard kind == .photo, let pngData else { return nil }
        let limit = min(max(1, maxSide), Self.maximumPhotoSide)
        return autoreleasepool {
            guard let source = CGImageSourceCreateWithData(
                pngData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary
            ), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: limit,
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary), image.width > 0, image.width == image.height,
                  image.width <= limit else { return nil }
            return image
        }
    }

    /// Folder previews retain these small pixels rather than the full imported
    /// photo. The source artwork on disk is never changed. Failure returns nil
    /// so callers can fall back without retaining a full-size photo by accident.
    public func thumbnail(maxSide: Int = 32) -> CustomIcon? {
        guard kind == .photo else { return self }
        return autoreleasepool {
            guard let image = decodedPhoto(maxSide: maxSide),
                  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: nil, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return nil }

            // Redrawing uses a known compact color profile and carries no source
            // properties (including location, author, or other photo metadata).
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard let pixels = context.makeImage() else { return nil }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, pixels, nil)
            guard CGImageDestinationFinalize(destination),
                  data.length <= image.width * image.height * 4 + 4_096 else { return nil }
            return Self.photo(pngData: data as Data, backgroundHex: backgroundHex)
        }
    }
}
