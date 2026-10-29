import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum IconPhotoImportError: Error, Equatable, Sendable {
    case invalidImage, unsupportedFormat, tooManyBytes, tooManyPixels
}

/// Prepares a still image for the crop editor without retaining its full-size
/// decoded pixels. This does not crop, save, fetch, or modify the source bytes.
public enum IconPhotoImport {
    public static let maximumInputBytes = 30 * 1_024 * 1_024
    public static let maximumSourceSide = 16_384
    public static let maximumSourcePixels = 80_000_000
    public static let maximumPreviewSide = 1_024

    /// Accepts one complete PNG, JPEG, HEIC or HEIF image, identified by ImageIO
    /// rather than its filename. Animated images and image collections are not
    /// imported. EXIF orientation is applied; alpha is not flattened.
    public static func prepare(_ data: Data) throws -> CGImage {
        guard data.count <= maximumInputBytes else { throw IconPhotoImportError.tooManyBytes }
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, [
                kCGImageSourceShouldCache: false,
              ] as CFDictionary),
              let type = CGImageSourceGetType(source) as String?
        else { throw IconPhotoImportError.invalidImage }

        let supported = [UTType.png.identifier, UTType.jpeg.identifier, UTType.heic.identifier, UTType.heif.identifier]
        guard supported.contains(type) else { throw IconPhotoImportError.unsupportedFormat }
        guard CGImageSourceGetStatus(source) == .statusComplete else { throw IconPhotoImportError.invalidImage }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { throw IconPhotoImportError.invalidImage }
        guard count == 1 else { throw IconPhotoImportError.unsupportedFormat }
        guard CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { throw IconPhotoImportError.invalidImage }
        // Division avoids an overflow even if a hostile header advertises an
        // enormous dimension. All limits are checked before decoding pixels.
        guard width <= maximumSourceSide, height <= maximumSourceSide,
              width <= maximumSourcePixels / height
        else { throw IconPhotoImportError.tooManyPixels }

        let complete: Bool
        switch type {
        case UTType.png.identifier:
            complete = DirectLaunchIcons.hasCompleteImageContainer(data, type: type)
        case UTType.jpeg.identifier:
            complete = completeJPEG(data)
        default:
            complete = completeHEIFContainer(data)
        }
        guard complete else { throw IconPhotoImportError.invalidImage }

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPreviewSide,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldAllowFloat: false,
        ] as CFDictionary),
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              image.width > 0, image.height > 0,
              image.width <= maximumPreviewSide, image.height <= maximumPreviewSide
        else { throw IconPhotoImportError.invalidImage }
        return image
    }

    /// Check segment boundaries and require an end marker after a scan. ImageIO
    /// can otherwise recover a JPEG whose original final bytes never arrived.
    /// Scan data allows escaped FF bytes and restart markers, including the
    /// multiple scans of a progressive JPEG.
    private static func completeJPEG(_ data: Data) -> Bool {
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return false }
            var offset = 2
            var sawScan = false
            while offset < bytes.count {
                guard bytes[offset] == 0xFF else { return false }
                while offset < bytes.count, bytes[offset] == 0xFF { offset += 1 }
                guard offset < bytes.count else { return false }
                let marker = bytes[offset]
                offset += 1
                if marker == 0xD9 { return sawScan && offset == bytes.count }
                // These have no length and are only legal within entropy data
                // (restart), or at the very beginning (start of image).
                guard marker != 0, marker != 0xD8, marker != 1,
                      !(0xD0...0xD7).contains(marker), offset <= bytes.count - 2
                else { return false }
                let length = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
                guard length >= 2, length <= bytes.count - offset else { return false }
                offset += length
                if marker != 0xDA { continue }
                guard length >= 6 else { return false }
                sawScan = true
                let scanStart = offset
                while offset < bytes.count {
                    if bytes[offset] != 0xFF { offset += 1; continue }
                    let markerStart = offset
                    while offset < bytes.count, bytes[offset] == 0xFF { offset += 1 }
                    guard offset < bytes.count else { return false }
                    let next = bytes[offset]
                    if next == 0 || (0xD0...0xD7).contains(next) { offset += 1; continue }
                    offset = markerStart
                    break
                }
                guard offset > scanStart else { return false }
            }
            return false
        }
    }

    /// HEIF stores image extents inside ISO BMFF boxes. Reject a partial box or
    /// missing payload before decoding; ImageIO additionally validates the
    /// referenced primary-image data. Auxiliary depth/HDR items are not removed.
    private static func completeHEIFContainer(_ data: Data) -> Bool {
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            func word(_ offset: Int) -> UInt64 {
                UInt64(bytes[offset]) << 24 | UInt64(bytes[offset + 1]) << 16
                    | UInt64(bytes[offset + 2]) << 8 | UInt64(bytes[offset + 3])
            }
            var offset = 0
            var hasFileType = false
            var hasMetadata = false
            while offset < bytes.count {
                guard bytes.count - offset >= 8 else { return false }
                var length = word(offset)
                let type = word(offset + 4)
                var header = 8
                if length == 1 {
                    guard bytes.count - offset >= 16 else { return false }
                    length = word(offset + 8) << 32 | word(offset + 12)
                    header = 16
                } else if length == 0 {
                    length = UInt64(bytes.count - offset)
                }
                guard length >= header, length <= UInt64(bytes.count - offset) else { return false }
                if type == 0x66747970 { // ftyp
                    guard offset == 0, length >= header + 8 else { return false }
                    hasFileType = true
                }
                if type == 0x6D657461 { // meta
                    guard length >= header + 4 else { return false }
                    hasMetadata = true
                }
                offset += Int(length)
            }
            return hasFileType && hasMetadata
        }
    }
}
