/// Optional custom artwork for each appearance. A missing standard image keeps
/// the existing automatic artwork; a missing dark image inherits the standard.
/// At least one image is required for a durable custom-artwork record.
public struct CustomIconVariants: Codable, Sendable, Equatable {
    public let standard: CustomIcon?
    public let dark: CustomIcon?

    public init(standard: CustomIcon? = nil, dark: CustomIcon? = nil) {
        self.standard = standard
        self.dark = dark
    }

    public var isValid: Bool {
        (standard != nil || dark != nil)
            && (standard?.isValid ?? true) && (dark?.isValid ?? true)
    }

    /// Counts artwork records containing a photo, not the number of photo files.
    public var containsPhoto: Bool { standard?.kind == .photo || dark?.kind == .photo }

    /// Includes an explicitly chosen date icon in either appearance, even when
    /// the current environment displays the other side.
    public var containsDate: Bool { standard?.kind == .date || dark?.kind == .date }

    /// Nil asks the caller to retain its existing App Store/symbol fallback.
    public func resolved(isDark: Bool) -> CustomIcon? { isDark ? dark ?? standard : standard }

    /// Each existing variant is downsampled independently. No fallback image is
    /// duplicated, and a failed thumbnail never retains its full-size source.
    public func thumbnail(maxSide: Int = 32) -> CustomIconVariants? {
        let result = CustomIconVariants(standard: standard?.thumbnail(maxSide: maxSide),
                                        dark: dark?.thumbnail(maxSide: maxSide))
        return result.isValid ? result : nil
    }

    private enum CodingKeys: String, CodingKey { case standard, dark }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(standard: try values.decodeIfPresent(CustomIcon.self, forKey: .standard),
                  dark: try values.decodeIfPresent(CustomIcon.self, forKey: .dark))
        guard isValid else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Empty custom icon variants"))
        }
    }
}
