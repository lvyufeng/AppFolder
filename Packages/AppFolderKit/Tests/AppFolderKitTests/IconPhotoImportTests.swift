import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AppFolderKit

@Suite("File photo import")
struct IconPhotoImportTests {
    @Test("A crop preview downsamples instead of cropping or flattening transparent pixels")
    func transparentPreview() throws {
        let context = try #require(CGContext(data: nil, width: 2_048, height: 1_024, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.clear(.init(x: 0, y: 0, width: 2_048, height: 1_024))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(.init(x: 1_024, y: 0, width: 1_024, height: 1_024))
        let original = try #require(context.makeImage())
        let preview = try IconPhotoImport.prepare(encode(original, type: .png))
        #expect(preview.width == 1_024 && preview.height == 512)
        let pixels = try rgba(preview)
        #expect(pixels[(256 * preview.width + 256) * 4 + 3] == 0)
        let opaque = (256 * preview.width + 768) * 4
        #expect(pixels[opaque] > pixels[opaque + 2] && pixels[opaque + 3] == 255)
    }

    @Test("PNG and JPEG previews retain their aspect ratio and small sources are not enlarged", arguments: [UTType.png, UTType.jpeg])
    func supportedStillFormats(type: UTType) throws {
        let image = try rgb(width: 96, height: 48)
        let data = try encode(image, type: type)
        let original = data
        let preview = try IconPhotoImport.prepare(data)
        #expect(preview.width == 96 && preview.height == 48)
        #expect(data == original)
    }

    @Test("JPEG EXIF orientations are applied to the crop preview", arguments: Array(1...8))
    func orientation(value: Int) throws {
        let image = try rgb(width: 96, height: 48)
        let data = try encode(image, type: .jpeg, properties: [kCGImagePropertyOrientation: value])
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyOrientation] as? Int == value)
        let preview = try IconPhotoImport.prepare(data)
        #expect(preview.width == (value >= 5 ? 48 : 96))
        #expect(preview.height == (value >= 5 ? 96 : 48))
        if value == 1 || value == 3 {
            let pixels = try rgba(preview)
            let left = (24 * preview.width + 12) * 4
            // The left half was red; a 180-degree orientation moves it right.
            #expect((pixels[left] > pixels[left + 2]) == (value == 1))
        }
    }

    @Test("A generated 48-megapixel camera-sized photo is accepted and returns a bounded crop preview")
    func largeCameraPhoto() throws {
        let width = 8_064, height = 6_048
        let data = try encode(gray(width: width, height: height), type: .jpeg)
        #expect(data.count < IconPhotoImport.maximumInputBytes)
        let preview = try IconPhotoImport.prepare(data)
        #expect(preview.width == 1_024 && preview.height == 768)
    }

    @Test("Generated HEIC is accepted, but missing payload bytes are rejected")
    func heic() throws {
        // Generated with ImageIO from a 256x128 sRGB bitmap containing only red
        // and blue halves. Embedded because HEVC encoding needs a system service
        // unavailable inside the test sandbox; no personal image is included.
        let data = try #require(Data(base64Encoded: "AAAAJGZ0eXBoZWljAAAAAG1pZjFNaVBybWlhZk1pSEJoZWljAAABhG1ldGEAAAAAAAAAIWhkbHIAAAAAAAAAAHBpY3QAAAAAAAAAAAAAAAAAAAAAJGRpbmYAAAAcZHJlZgAAAAAAAAABAAAADHVybCAAAAABAAAADnBpdG0AAAAAAAEAAAAjaWluZgAAAAAAAQAAABVpbmZlAgAAAAABAABodmMxAAAAAORpcHJwAAAAw2lwY28AAAATY29scm5jbHgAAgACAAaAAAAADGNsbGkAywBAAAAAFGlzcGUAAAAAAAABAAAAAIAAAAAJaXJvdAAAAAAQcGl4aQAAAAADCAgIAAAAb2h2Y0MBA3AAAACwAAAAAAAe8AD8/fj4AAALA6AAAQAXQAEMAf//A3AAAAMAsAAAAwAAAwAecCShAAEAIUIBAQNwAAADALAAAAMAAAMAHqAICAgWIe5FlU3AgIGAIKIAAQAJRAHAYXLIQFMkAAAAGWlwbWEAAAAAAAAAAQABBoECAwWGhAAAAB5pbG9jAAAAAEQAAAEAAQAAAAEAAAG4AAAATQAAAAFtZGF0AAAAAAAAAF0AAABJKAGvkNGUTEaBfP/8ZIf/+I77L8d3z7Fv2eax//sztffw5Qf/3Mq4XxOkgD5txfznNq53V/IIIrFiJHd0kkAMQAqvXrebGQC1gA=="))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.heic.identifier)
        let preview = try IconPhotoImport.prepare(data)
        #expect(preview.width == 256 && preview.height == 128)
        for count in [1, 7, data.count / 2] {
            #expect(throws: IconPhotoImportError.invalidImage) {
                try IconPhotoImport.prepare(Data(data.dropLast(count)))
            }
        }
        // A valid, unknown top-level box is not mistaken for a truncation.
        var padded = data
        padded.append(contentsOf: [0, 0, 0, 8, 0x66, 0x72, 0x65, 0x65])
        #expect(try IconPhotoImport.prepare(padded).width == 256)
        var extendsToEnd = data
        extendsToEnd.append(contentsOf: [0, 0, 0, 0, 0x66, 0x72, 0x65, 0x65])
        #expect(try IconPhotoImport.prepare(extendsToEnd).height == 128)
        var invalidBox = data
        invalidBox.append(contentsOf: [0, 0, 0, 1, 0x66, 0x72, 0x65, 0x65])
        invalidBox.append(contentsOf: Array(repeating: 255, count: 8))
        #expect(throws: IconPhotoImportError.invalidImage) { try IconPhotoImport.prepare(invalidBox) }
    }

    @Test("Progressive JPEG scans remain supported")
    func progressiveJPEG() throws {
        let data = try encode(rgb(width: 256, height: 128), type: .jpeg,
                              properties: [kCGImagePropertyJFIFDictionary: [kCGImagePropertyJFIFIsProgressive: true]])
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let jfif = try #require(properties[kCGImagePropertyJFIFDictionary] as? [CFString: Any])
        #expect(jfif[kCGImagePropertyJFIFIsProgressive] as? Bool == true)
        #expect(try IconPhotoImport.prepare(data).width == 256)
    }

    @Test("Real source type governs acceptance, including unsupported still and animated formats")
    func unsupportedFormats() throws {
        for type in [UTType.gif, UTType.tiff, UTType.bmp] {
            let bytes = try encode(rgb(width: 64, height: 32), type: type)
            #expect(throws: IconPhotoImportError.unsupportedFormat) { try IconPhotoImport.prepare(bytes) }
        }
        let frames = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(frames, UTType.png.identifier as CFString, 2, nil))
        let frame = try rgb(width: 64, height: 32)
        CGImageDestinationAddImage(destination, frame, nil)
        CGImageDestinationAddImage(destination, frame, nil)
        #expect(CGImageDestinationFinalize(destination))
        let source = try #require(CGImageSourceCreateWithData(frames, nil))
        #expect(CGImageSourceGetCount(source) == 2)
        #expect(throws: IconPhotoImportError.unsupportedFormat) { try IconPhotoImport.prepare(frames as Data) }
    }

    @Test("Truncated or checksum-damaged source bytes cannot become recovered previews")
    func malformed() throws {
        for bytes in [Data(), Data("<html>Not an image</html>".utf8), Data([137, 80, 78, 71, 13, 10, 26, 10])] {
            #expect(throws: IconPhotoImportError.invalidImage) { try IconPhotoImport.prepare(bytes) }
        }
        for type in [UTType.png, UTType.jpeg] {
            let bytes = try encode(rgb(width: 256, height: 128), type: type)
            for count in [1, 2, bytes.count / 2] {
                #expect(throws: IconPhotoImportError.invalidImage) { try IconPhotoImport.prepare(Data(bytes.dropLast(count))) }
            }
        }
        var corrupted = try encode(rgb(width: 64, height: 32), type: .png)
        corrupted[corrupted.count - 1] ^= 1 // IEND checksum, after all pixel data.
        #expect(throws: IconPhotoImportError.invalidImage) { try IconPhotoImport.prepare(corrupted) }
    }

    @Test("Source side and pixel count are bounded before oversized image payloads can decode")
    func dimensionLimits() throws {
        let boundary = try encode(rgb(width: IconPhotoImport.maximumSourceSide, height: 1), type: .png)
        #expect(try IconPhotoImport.prepare(boundary).width == 1_024)
        let tooWide = try encode(rgb(width: IconPhotoImport.maximumSourceSide + 1, height: 1), type: .png)
        #expect(throws: IconPhotoImportError.tooManyPixels) { try IconPhotoImport.prepare(tooWide) }
        let tooManyPixels = try encode(gray(width: 10_000, height: 8_001), type: .jpeg)
        #expect(tooManyPixels.count < IconPhotoImport.maximumInputBytes)
        #expect(throws: IconPhotoImportError.tooManyPixels) { try IconPhotoImport.prepare(tooManyPixels) }
        let pixelBoundary = try encode(gray(width: 10_000, height: 8_000), type: .jpeg)
        #expect(try IconPhotoImport.prepare(pixelBoundary).width == 1_024)
    }

    @Test("The byte limit is inclusive and checked before image parsing")
    func inputSize() {
        let boundary = Data(repeating: 0, count: IconPhotoImport.maximumInputBytes)
        #expect(throws: IconPhotoImportError.invalidImage) { try IconPhotoImport.prepare(boundary) }
        let oversized = Data(repeating: 0, count: IconPhotoImport.maximumInputBytes + 1)
        #expect(throws: IconPhotoImportError.tooManyBytes) { try IconPhotoImport.prepare(oversized) }
    }

    private func rgb(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(.init(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(.init(x: width / 2, y: 0, width: width - width / 2, height: height))
        return try #require(context.makeImage())
    }

    private func encode(_ image: CGImage, type: UTType, properties: [CFString: Any] = [:]) throws -> Data {
        let bytes = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(bytes, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
        return bytes as Data
    }

    private func rgba(_ image: CGImage) throws -> [UInt8] {
        let context = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                             bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: .init(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
        return Array(UnsafeBufferPointer(start: bytes, count: image.width * image.height * 4))
    }

    private func gray(width: Int, height: Int) throws -> CGImage {
        let bytes = Data(repeating: 127, count: width * height)
        let provider = try #require(CGDataProvider(data: bytes as CFData))
        return try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                                   bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                   bitmapInfo: [], provider: provider, decode: nil,
                                   shouldInterpolate: false, intent: .defaultIntent))
    }
}
