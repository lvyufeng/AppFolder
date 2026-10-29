import Foundation
import ImageIO

/// A user's artwork for a named widget action. It never changes the action itself.
public struct CustomIcon: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case symbol, emoji, photo, date
    }

    public let kind: Kind
    /// An SF Symbol name or up to two text/emoji characters. Empty for a photo or date.
    public let value: String
    public let backgroundHex: String
    public let pngData: Data?

    /// Small enough to decode several visible tiles within a widget's memory budget.
    public static let maximumPhotoBytes = 512 * 1_024
    public static let maximumPhotoSide = 256

    public static let symbols = CustomIconSymbolCatalog.entries.map(\.id)

    public static func symbol(_ name: String, backgroundHex: String = "#0A84FF") -> CustomIcon? {
        make(kind: .symbol, value: name, backgroundHex: backgroundHex, pngData: nil)
    }

    /// Explicitly selected local-date artwork. Only its configuration is saved;
    /// the renderer supplies the date, locale and time zone without reading events.
    public static func date(backgroundHex: String = "#0A84FF") -> CustomIcon? {
        make(kind: .date, value: "", backgroundHex: backgroundHex, pngData: nil)
    }

    public static func emoji(_ text: String, backgroundHex: String = "#0A84FF") -> CustomIcon? {
        guard !text.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else { return nil }
        return make(kind: .emoji, value: text.trimmingCharacters(in: .whitespaces),
                    backgroundHex: backgroundHex, pngData: nil)
    }

    /// Accepts an already cropped, metadata-free PNG produced by the app's image importer.
    public static func photo(pngData: Data, backgroundHex: String = "#0A84FF") -> CustomIcon? {
        make(kind: .photo, value: "", backgroundHex: backgroundHex, pngData: pngData)
    }

    public var isValid: Bool {
        Self.make(kind: kind, value: value, backgroundHex: backgroundHex, pngData: pngData) != nil
    }

    private init(kind: Kind, value: String, backgroundHex: String, pngData: Data?) {
        self.kind = kind
        self.value = value
        self.backgroundHex = backgroundHex
        self.pngData = pngData
    }

    private static func make(kind: Kind, value: String, backgroundHex: String, pngData: Data?) -> CustomIcon? {
        guard let color = FolderTint(hex: backgroundHex) else { return nil }
        switch kind {
        case .symbol:
            guard CustomIconSymbolCatalog.entry(id: value) != nil, pngData == nil else { return nil }
        case .date:
            guard value.isEmpty, pngData == nil else { return nil }
        case .emoji:
            guard pngData == nil, (1...2).contains(value.count), value.utf8.count <= 128 else { return nil }
            let scalars = value.unicodeScalars
            let containsEmoji = scalars.contains { $0.properties.isEmojiPresentation }
            var hasVisibleBase = false
            for scalar in scalars {
                switch scalar.properties.generalCategory {
                case .control, .lineSeparator, .paragraphSeparator, .spaceSeparator, .unassigned, .privateUse:
                    return nil
                case .format:
                    // ZWJ joins family/profession emoji. Other format characters,
                    // including bidi overrides and invisible separators, are not artwork.
                    guard scalar.value == 0x200D, containsEmoji else { return nil }
                case .nonspacingMark, .spacingMark, .enclosingMark:
                    break
                default:
                    hasVisibleBase = true
                }
            }
            guard hasVisibleBase else { return nil }
        case .photo:
            guard value.isEmpty, let pngData, validPNG(pngData) else { return nil }
        }
        return CustomIcon(kind: kind, value: value, backgroundHex: color.hex, pngData: pngData)
    }

    private static func validPNG(_ data: Data) -> Bool {
        guard !data.isEmpty, data.count <= maximumPhotoBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == "public.png",
              // A successful ImageIO decode can be a recovered, partial PNG.
              // Verify the original bytes, without replacing the user's artwork.
              DirectLaunchIcons.hasCompleteImageContainer(data, type: "public.png"),
              CGImageSourceGetCount(source) == 1,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width == height, (1...maximumPhotoSide).contains(width),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return false }
        return image.width == width && image.height == height
    }

    private enum CodingKeys: String, CodingKey { case kind, value, backgroundHex, pngData }

    /// Disk data goes through the same validation as user input.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try values.decode(Kind.self, forKey: .kind)
        let value = try values.decode(String.self, forKey: .value)
        let background = try values.decode(String.self, forKey: .backgroundHex)
        let png = try values.decodeIfPresent(Data.self, forKey: .pngData)
        guard let icon = Self.make(kind: kind, value: value, backgroundHex: background, pngData: png) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid custom icon"))
        }
        self = icon
    }
}
