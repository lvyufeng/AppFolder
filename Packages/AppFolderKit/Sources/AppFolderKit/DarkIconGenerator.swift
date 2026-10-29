import CoreGraphics
import Foundation
import ImageIO

public enum DarkIconGenerationError: Error, Sendable, Equatable {
    case invalidImage, processingFailed
}

/// Produces a user-previewable local style, never an official App Store variant.
/// It does not fetch, save, change the launch target or mutate the source artwork.
public enum DarkIconGenerator {
    public enum Source: Sendable {
        case custom(CustomIcon)
        case cachedArtwork(Data)
    }

    public enum Treatment: String, Sendable { case semantic, graphic, photograph }

    public struct Result: Sendable {
        public let source: CustomIcon
        public let icon: CustomIcon
        public let treatment: Treatment
    }

    private static let background = "#1C1C1E"
    private static let sideLimit = CustomIcon.maximumPhotoSide
    private typealias RGB = SIMD3<Double>

    public static func generate(from source: Source) throws -> Result {
        try Task.checkCancellation()
        let original: CustomIcon
        let image: CGImage
        switch source {
        case .custom(let icon):
            guard icon.isValid else { throw DarkIconGenerationError.invalidImage }
            if icon.kind != .photo { return try semantic(icon) }
            guard let decoded = icon.decodedPhoto(maxSide: sideLimit) else { throw DarkIconGenerationError.invalidImage }
            original = icon
            image = decoded
        case .cachedArtwork(let data):
            // Reuse the established source-byte, dimension, completeness and
            // downsampling limits. Non-square sources are never silently cropped.
            guard let decoded = DirectLaunchIcons.artworkThumbnail(data, maxPixelSize: sideLimit),
                  decoded.width == decoded.height,
                  let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int, width == height
            else { throw DarkIconGenerationError.invalidImage }
            image = decoded
            let pixels = try rgba(image)
            original = try encoded(pixels, side: image.width, backgroundHex: "#F2F2F7")
        }
        try Task.checkCancellation()
        var pixels = try rgba(image)
        let classification = try classify(pixels, side: image.width)
        for row in 0..<image.height {
            try Task.checkCancellation()
            for column in 0..<image.width {
                let offset = (row * image.width + column) * 4
                let alpha = pixels[offset + 3]
                guard alpha > 0 else {
                    pixels[offset] = 0; pixels[offset + 1] = 0; pixels[offset + 2] = 0
                    continue
                }
                let rgb = straightRGB(pixels, offset: offset)
                let linear = linearRGB(rgb)
                let y = luminance(linear)
                let target: Double
                switch classification {
                case .brightGraphic:
                    // A simple bright canvas becomes a dark canvas and its
                    // dark marks become light. This is a whole-graphic style,
                    // not an inferred foreground mask or object segmentation.
                    let neutral = 0.85 - 0.83 * y
                    // Saturated marks need not become almost white: keep their
                    // color, lifting dark colors only to a readable 0.24 floor.
                    let color = smoothstep(0.08, 0.30, rgb.max() - rgb.min())
                    let colored = max(0.24, min(y, 0.45))
                    target = neutral * (1 - color) + colored * color
                case .transparentGraphic:
                    // Alpha already defines the silhouette. Keep bright marks
                    // bright and lift dark marks against the dark backing plate.
                    let color = smoothstep(0.08, 0.30, rgb.max() - rgb.min())
                    target = max(y, 0.55 * (1 - color) + 0.24 * color)
                case .photograph:
                    // Strictly increasing: retain tonal order and midtones,
                    // soften highlights, and lift only the deepest shadows.
                    target = y - 0.25 * smoothstep(0.35, 0.95, y)
                        + 0.015 * (1 - smoothstep(0, 0.18, y))
                }
                let adjusted = remap(linear, from: y, to: target)
                for channel in 0..<3 {
                    pixels[offset + channel] = UInt8(clamping: Int((toEncoded(adjusted[channel]) * Double(alpha)).rounded()))
                }
                // Alpha is deliberately never reassigned, including soft edges.
            }
        }
        try Task.checkCancellation()
        let output = try encoded(pixels, side: image.width, backgroundHex: background)
        return Result(source: original, icon: output,
                      treatment: classification == .photograph ? .photograph : .graphic)
    }

    private static func semantic(_ source: CustomIcon) throws -> Result {
        guard let tint = FolderTint(hex: source.backgroundHex) else { throw DarkIconGenerationError.invalidImage }
        let linear = linearRGB(RGB(tint.red, tint.green, tint.blue))
        let y = luminance(linear)
        let scale = y > 0.06 ? 0.06 / y : 1
        let rgb = RGB(toEncoded(linear.x * scale), toEncoded(linear.y * scale), toEncoded(linear.z * scale))
        let hex = FolderTint(red: rgb[0], green: rgb[1], blue: rgb[2]).hex
        let icon: CustomIcon?
        switch source.kind {
        case .symbol: icon = .symbol(source.value, backgroundHex: hex)
        case .emoji: icon = .emoji(source.value, backgroundHex: hex)
        case .date: icon = .date(backgroundHex: hex)
        case .photo: icon = nil
        }
        guard let icon else { throw DarkIconGenerationError.processingFailed }
        try Task.checkCancellation()
        return Result(source: source, icon: icon, treatment: .semantic)
    }

    private enum Classification { case brightGraphic, transparentGraphic, photograph }

    private static func classify(_ pixels: [UInt8], side: Int) throws -> Classification {
        var histogram: [Int: Int] = [:]
        var weight = 0
        var transparent = 0
        var darkWeight = 0
        var brightWeight = 0
        var minimumVisibleLuminance = 1.0
        let borderWidth = max(1, side / 32)
        var edge: [RGB] = []
        var edgeCount = 0
        for row in 0..<side {
            try Task.checkCancellation()
            for column in 0..<side {
                let offset = (row * side + column) * 4
                let alpha = Int(pixels[offset + 3])
                if alpha < 250 { transparent += 1 }
                let isEdge = row < borderWidth || row >= side - borderWidth
                    || column < borderWidth || column >= side - borderWidth
                if isEdge { edgeCount += 1 }
                guard alpha > 0 else { continue }
                let rgb = straightRGB(pixels, offset: offset)
                let y = luminance(linearRGB(rgb))
                minimumVisibleLuminance = min(minimumVisibleLuminance, y)
                if y < 0.20 { darkWeight += alpha }
                if y >= 0.60 { brightWeight += alpha }
                // Five bits per channel distinguishes photographic gradients
                // while tolerating the small antialiasing fringe of flat logos.
                let red = min(31, Int(rgb.x * 32)), green = min(31, Int(rgb.y * 32)), blue = min(31, Int(rgb.z * 32))
                histogram[(red << 10) | (green << 5) | blue, default: 0] += alpha
                weight += alpha
                if isEdge, alpha >= 250 { edge.append(rgb) }
            }
        }
        guard weight > 0 else { throw DarkIconGenerationError.invalidImage }
        let simple = histogram.values.sorted(by: >).prefix(16).reduce(0, +) * 100 >= weight * 95
        guard simple else { return .photograph }
        // A bright transparent frame/U-shaped mark may touch every outer edge.
        // With no darker visible content, preserve its light foreground instead
        // of inferring a bright canvas solely from the perimeter.
        if transparent * 100 >= side * side, minimumVisibleLuminance >= 0.60 { return .transparentGraphic }
        // A bright canvas can have transparent rounded corners. Inspect its
        // opaque border first; alpha alone is not a foreground/background mask.
        if !edge.isEmpty, edge.count * 100 >= edgeCount * 50 {
            let medians = RGB(edge.map(\.x).sorted()[edge.count / 2], edge.map(\.y).sorted()[edge.count / 2],
                              edge.map(\.z).sorted()[edge.count / 2])
            let uniform = edge.filter { pixel in (0..<3).allSatisfy { abs(pixel[$0] - medians[$0]) <= 0.08 } }.count
            // A strongly colored canvas needs different foreground decisions.
            // Do not mistake a yellow panel for the neutral canvas handled here.
            if uniform * 100 >= edge.count * 95, luminance(linearRGB(medians)) >= 0.60,
               medians.max() - medians.min() <= 0.08 { return .brightGraphic }
        }
        if transparent * 100 >= side * side {
            // A transparent frame around a white panel with dark marks must not
            // lift both the panel and its text. Without a reliable bright border,
            // mixed dark/light content keeps the conservative photo treatment.
            if darkWeight * 100 >= weight * 5 && brightWeight * 100 >= weight * 25 { return .photograph }
            return .transparentGraphic
        }
        return .photograph
    }

    private static func rgba(_ image: CGImage) throws -> [UInt8] {
        guard image.width > 0, image.width == image.height, image.width <= sideLimit else {
            throw DarkIconGenerationError.invalidImage
        }
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let rendered = bytes.withUnsafeMutableBytes { storage in
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: storage.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4, space: colorSpace,
                                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard rendered else { throw DarkIconGenerationError.processingFailed }
        return bytes
    }

    private static func encoded(_ bytes: [UInt8], side: Int, backgroundHex: String) throws -> CustomIcon {
        try Task.checkCancellation()
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: side * 4, space: colorSpace,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw DarkIconGenerationError.processingFailed }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            throw DarkIconGenerationError.processingFailed
        }
        // Only a fresh sRGB pixel image is encoded; no source metadata is copied.
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), data.length <= CustomIcon.maximumPhotoBytes,
              let result = CustomIcon.photo(pngData: data as Data, backgroundHex: backgroundHex) else {
            throw DarkIconGenerationError.processingFailed
        }
        try Task.checkCancellation()
        return result
    }

    private static func straightRGB(_ pixels: [UInt8], offset: Int) -> RGB {
        let alpha = Double(pixels[offset + 3])
        guard alpha > 0 else { return .zero }
        return RGB(min(1, Double(pixels[offset]) / alpha), min(1, Double(pixels[offset + 1]) / alpha),
                   min(1, Double(pixels[offset + 2]) / alpha))
    }

    // Scaling toward black or mixing toward white reaches the target luminance
    // without rotating RGB hue or leaving the gamut. It does not promise exact
    // brand color preservation or photographic object recognition.
    private static func remap(_ rgb: RGB, from source: Double, to target: Double) -> RGB {
        if target <= source { return rgb * (source > 0 ? target / source : 0) }
        let amount = (target - source) / max(1e-12, 1 - source)
        return rgb + (RGB(repeating: 1) - rgb) * amount
    }
    private static func linearRGB(_ rgb: RGB) -> RGB { RGB(toLinear(rgb.x), toLinear(rgb.y), toLinear(rgb.z)) }
    private static func luminance(_ rgb: RGB) -> Double { 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2] }
    private static func toLinear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
    private static func toEncoded(_ value: Double) -> Double {
        let value = min(1, max(0, value))
        return value <= 0.0031308 ? 12.92 * value : 1.055 * pow(value, 1 / 2.4) - 0.055
    }
    private static func smoothstep(_ low: Double, _ high: Double, _ value: Double) -> Double {
        let t = min(1, max(0, (value - low) / (high - low)))
        return t * t * (3 - 2 * t)
    }
}
