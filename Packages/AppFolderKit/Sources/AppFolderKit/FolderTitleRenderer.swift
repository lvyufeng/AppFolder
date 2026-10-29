import CoreGraphics
import CoreText
import Foundation

struct FolderTitleRGBA: Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    var isValid: Bool {
        [red, green, blue, alpha].allSatisfy { $0.isFinite && (0...1).contains($0) }
    }

    var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

struct FolderTitleRenderRequest: Hashable, Sendable {
    let text: String
    let fontSize: CGFloat
    let width: CGFloat
    let availableHeight: CGFloat?
    let minimumScaleFactor: CGFloat
    let weight: CGFloat
    let displayScale: CGFloat
    let foreground: FolderTitleRGBA
    let outline: FolderTitleRGBA?
    let outlineWidth: CGFloat
}

struct FolderTitleRaster: @unchecked Sendable {
    let image: CGImage
    let size: CGSize
    let fittedFontSize: CGFloat
    let isTruncated: Bool
    let lineWidth: CGFloat

    var byteCost: Int { image.bytesPerRow * image.height }
}

/// Core Text applies a real glyph stroke, measured in percent of the fitted
/// font size. No blur, offset copies, UIKit view, or image file is involved.
/// https://developer.apple.com/documentation/coretext/kctstrokewidthattributename
enum FolderTitleRenderer {
    static let maximumPixelWidth = 256
    static let maximumPixelHeight = 64
    static let maximumPixels = 8_192

    static func render(_ request: FolderTitleRenderRequest) -> FolderTitleRaster? {
        guard !request.text.isEmpty, request.text.count <= SavedGroup.maximumNameLength,
              request.text.utf8.count <= 512,
              !request.text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              request.fontSize.isFinite, (0.1...128).contains(request.fontSize),
              request.width.isFinite, (0.1...2_048).contains(request.width),
              request.minimumScaleFactor.isFinite, (0.1...1).contains(request.minimumScaleFactor),
              request.weight.isFinite, (-1...1).contains(request.weight),
              request.displayScale.isFinite, request.displayScale > 0,
              request.outlineWidth.isFinite, (0...1.5).contains(request.outlineWidth),
              request.foreground.isValid, request.outline?.isValid ?? true else { return nil }
        if let height = request.availableHeight, !height.isFinite || height <= 0 || height > 512 { return nil }
        return autoreleasepool { draw(request) }
    }

    private static func font(size: CGFloat, weight: CGFloat) -> CTFont? {
        guard let system = CTFontCreateUIFontForLanguage(.system, size, nil) else { return nil }
        guard weight != 0 else { return system }
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(system), [
            kCTFontTraitsAttribute: [kCTFontWeightTrait: weight]
        ] as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    private static func line(_ text: String, size: CGFloat, request: FolderTitleRenderRequest,
                             includesOutline: Bool = true) -> CTLine? {
        guard let font = font(size: size, weight: request.weight) else { return nil }
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): request.foreground.cgColor,
        ]
        if includesOutline, let outline = request.outline, request.outlineWidth > 0 {
            attributes[NSAttributedString.Key(kCTStrokeColorAttributeName as String)] = outline.cgColor
            attributes[NSAttributedString.Key(kCTStrokeWidthAttributeName as String)] = 100 * request.outlineWidth / size
        }
        // Core Text performs Unicode shaping, font fallback and bidirectional
        // ordering. Do not split into Character/glyph paths: color emoji and
        // joining scripts need their original runs.
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    private static func typographicSize(_ line: CTLine) -> CGSize {
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        return CGSize(width: width, height: ascent + descent + leading)
    }

    private static func draw(_ request: FolderTitleRenderRequest) -> FolderTitleRaster? {
        let stroke = request.outline == nil ? 0 : request.outlineWidth
        let padding = stroke > 0 ? stroke / 2 + 0.5 : 0
        let usableWidth = request.width - padding * 2
        guard usableWidth > 0,
              let original = line(request.text, size: request.fontSize, request: request) else { return nil }
        let originalSize = typographicSize(original)
        let height = min(request.availableHeight ?? (originalSize.height + 2 * padding),
                         originalSize.height + 2 * padding)
        let usableHeight = height - 2 * padding
        let minimumSize = request.fontSize * request.minimumScaleFactor
        guard usableHeight > 0 else { return nil }

        var fittedSize = request.fontSize
        var fittedLine = original
        var truncated = false
        if originalSize.width > usableWidth || originalSize.height > usableHeight {
            guard let smallest = line(request.text, size: minimumSize, request: request) else { return nil }
            let smallestSize = typographicSize(smallest)
            guard smallestSize.height <= usableHeight else { return nil }
            fittedSize = minimumSize
            fittedLine = smallest
            if smallestSize.width <= usableWidth {
                // A bounded search accommodates fallback font metrics and
                // optical sizing, where widths are not exactly proportional.
                var low = minimumSize, high = request.fontSize
                for _ in 0..<7 {
                    let candidateSize = (low + high) / 2
                    guard let candidate = line(request.text, size: candidateSize, request: request) else { return nil }
                    let bounds = typographicSize(candidate)
                    if bounds.width <= usableWidth && bounds.height <= usableHeight {
                        low = candidateSize
                        fittedSize = candidateSize
                        fittedLine = candidate
                    } else {
                        high = candidateSize
                    }
                }
            } else {
                guard let token = line("…", size: minimumSize, request: request),
                      let shortened = CTLineCreateTruncatedLine(smallest, Double(usableWidth), .end, token) else { return nil }
                fittedLine = shortened
                truncated = true
            }
        }

        var fillLine: CTLine?
        if stroke > 0 {
            guard let filled = line(request.text, size: fittedSize, request: request, includesOutline: false) else { return nil }
            if truncated {
                guard let token = line("…", size: fittedSize, request: request, includesOutline: false),
                      let shortened = CTLineCreateTruncatedLine(filled, Double(usableWidth), .end, token) else { return nil }
                fillLine = shortened
            } else {
                fillLine = filled
            }
        }

        var scale = min(request.displayScale, 3)
        scale = min(scale, CGFloat(maximumPixelWidth) / request.width,
                    CGFloat(maximumPixelHeight) / height,
                    sqrt(CGFloat(maximumPixels) / (request.width * height)))
        let pixelWidth = max(1, Int(floor(request.width * scale)))
        let pixelHeight = max(1, Int(floor(height * scale)))
        guard pixelWidth <= maximumPixelWidth, pixelHeight <= maximumPixelHeight,
              pixelWidth * pixelHeight <= maximumPixels,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight,
                                      bitsPerComponent: 8, bytesPerRow: pixelWidth * 4,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.scaleBy(x: CGFloat(pixelWidth) / request.width, y: CGFloat(pixelHeight) / height)
        context.setShouldAntialias(true)
        context.setShouldSmoothFonts(false)
        context.textMatrix = .identity
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let lineWidth = CTLineGetTypographicBounds(fittedLine, &ascent, &descent, nil)
        let x = padding + CTLineGetPenOffsetForFlush(fittedLine, 0.5, Double(usableWidth))
        context.textPosition = CGPoint(x: x, y: (height - ascent - descent) / 2 + descent)
        CTLineDraw(fittedLine, context)
        if let fillLine {
            // A negative stroke-and-fill attribute draws the stroke over the
            // fill, which can erase small stems. Drawing the same shaped line
            // as a normal fill afterward preserves the original glyph weight.
            context.setTextDrawingMode(.fill)
            context.textPosition = CGPoint(x: x, y: (height - ascent - descent) / 2 + descent)
            CTLineDraw(fillLine, context)
        }
        guard let image = context.makeImage() else { return nil }
        return FolderTitleRaster(image: image, size: CGSize(width: request.width, height: height),
                                 fittedFontSize: fittedSize, isTruncated: truncated, lineWidth: lineWidth)
    }
}

/// Cost includes decoded pixels; item count alone cannot bound an image cache.
/// Keys use resolved colors, so light/dark changes never reuse old-color pixels.
final class FolderTitleRasterCache: @unchecked Sendable {
    static let shared = FolderTitleRasterCache()
    static let maximumCost = 2 * 1_024 * 1_024
    static let maximumEntries = 96
    private let costLimit: Int
    private let countLimit: Int
    private let lock = NSLock()
    private var entries: [FolderTitleRenderRequest: FolderTitleRaster] = [:]
    private var recency: [FolderTitleRenderRequest] = []
    private var cost = 0

    init(costLimit: Int = maximumCost, countLimit: Int = maximumEntries) {
        self.costLimit = max(0, costLimit)
        self.countLimit = max(0, countLimit)
    }

    var retainedCost: Int { lock.withLock { cost } }
    var retainedCount: Int { lock.withLock { entries.count } }

    func raster(for request: FolderTitleRenderRequest) -> FolderTitleRaster? {
        if let cached = lock.withLock({ () -> FolderTitleRaster? in
            guard let found = entries[request] else { return nil }
            touch(request)
            return found
        }) { return cached }
        guard let rendered = FolderTitleRenderer.render(request) else { return nil }
        return lock.withLock {
            if let cached = entries[request] { touch(request); return cached }
            guard countLimit > 0, rendered.byteCost <= costLimit else { return rendered }
            entries[request] = rendered
            cost += rendered.byteCost
            touch(request)
            while entries.count > countLimit || cost > costLimit {
                let oldest = recency.removeFirst()
                if let removed = entries.removeValue(forKey: oldest) { cost -= removed.byteCost }
            }
            return rendered
        }
    }

    private func touch(_ request: FolderTitleRenderRequest) {
        recency.removeAll { $0 == request }
        recency.append(request)
    }
}
