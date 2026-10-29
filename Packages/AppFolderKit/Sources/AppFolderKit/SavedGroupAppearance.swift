import Foundation

public enum SavedGroupIconSize: String, Codable, Sendable, CaseIterable {
    case small, medium, large

    public var scale: Double {
        switch self {
        case .small: 0.5
        case .medium: 0.75
        case .large: 1
        }
    }
}

public enum SavedGroupTitleOutlineWidth: String, Codable, Sendable, Hashable, CaseIterable {
    case thin, medium, thick

    public var points: Double {
        switch self {
        case .thin: 0.5
        case .medium: 1
        case .thick: 1.5
        }
    }
}

/// Durable presentation choices, separate from action identities and system
/// widget configuration. Invalid drafts cannot be decoded or saved as a group.
public struct SavedGroupAppearance: Codable, Sendable, Equatable {
    public var grid: FolderGrid
    public var showsTitles: Bool
    public var iconSize: SavedGroupIconSize
    public var plate: FolderPlate
    public var tintHex: String
    public var density: FolderDensity
    public var backButtonStyle: FolderBackButtonStyle
    /// Nil uses the established automatic geometry; explicit zero is distinct.
    public var spacing: Int?
    public var margin: Int?
    public var titleColorHex: String?
    public var titleOutlineHex: String?
    public var titleOutlineWidth: SavedGroupTitleOutlineWidth

    public init(
        grid: FolderGrid = .nine,
        showsTitles: Bool = true,
        iconSize: SavedGroupIconSize = .medium,
        plate: FolderPlate = .automatic,
        tintHex: String = "#0A84FF",
        density: FolderDensity = .standard,
        backButtonStyle: FolderBackButtonStyle = .chevronUp,
        spacing: Int? = nil,
        margin: Int? = nil,
        titleColorHex: String? = nil,
        titleOutlineHex: String? = nil,
        titleOutlineWidth: SavedGroupTitleOutlineWidth = .thin
    ) {
        self.grid = grid
        self.showsTitles = showsTitles
        self.iconSize = iconSize
        self.plate = plate
        // Preserve invalid input for validation instead of replacing it with a
        // different color. Valid spelling variations share one stored form.
        self.tintHex = FolderTint(hex: tintHex)?.hex ?? tintHex
        self.density = density
        self.backButtonStyle = backButtonStyle
        self.spacing = spacing
        self.margin = margin
        self.titleColorHex = titleColorHex.map { FolderTint(hex: $0)?.hex ?? $0 }
        self.titleOutlineHex = titleOutlineHex.map { FolderTint(hex: $0)?.hex ?? $0 }
        self.titleOutlineWidth = titleOutlineWidth
    }

    public static let `default` = SavedGroupAppearance()

    public var isValid: Bool {
        FolderTint(hex: tintHex) != nil
            && (spacing.map { (0...24).contains($0) } ?? true)
            && (margin.map { (0...40).contains($0) } ?? true)
            && (titleColorHex.map { FolderTint(hex: $0) != nil } ?? true)
            && (titleOutlineHex.map { FolderTint(hex: $0) != nil } ?? true)
    }

    public var validatedStyle: FolderStyle? {
        guard isValid, let tint = FolderTint(hex: tintHex) else { return nil }
        return FolderStyle(plate: plate, tint: tint, showsTitles: showsTitles,
                           iconScale: iconSize.scale, grid: grid, density: density, backButtonStyle: backButtonStyle,
                           spacing: spacing, margin: margin, titleTint: titleColorHex.flatMap(FolderTint.init(hex:)),
                           titleOutlineTint: titleOutlineHex.flatMap(FolderTint.init(hex:)), titleOutlineWidth: titleOutlineWidth)
    }

    /// A rendering fallback for an invalid unsaved draft. This does not repair
    /// its data: isValid stays false, and decoding, saving and export reject it.
    public var style: FolderStyle { validatedStyle ?? Self.default.style }

    var normalized: SavedGroupAppearance {
        var copy = self
        if let tint = FolderTint(hex: tintHex) { copy.tintHex = tint.hex }
        if let titleColorHex, let tint = FolderTint(hex: titleColorHex) { copy.titleColorHex = tint.hex }
        if let titleOutlineHex, let tint = FolderTint(hex: titleOutlineHex) { copy.titleOutlineHex = tint.hex }
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case grid, showsTitles, iconSize, plate, tintHex, density, backButtonStyle
        case spacing, margin, titleColorHex, titleOutlineHex, titleOutlineWidth
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        grid = try values.decode(FolderGrid.self, forKey: .grid)
        showsTitles = try values.decode(Bool.self, forKey: .showsTitles)
        iconSize = try values.decode(SavedGroupIconSize.self, forKey: .iconSize)
        plate = try values.decode(FolderPlate.self, forKey: .plate)
        tintHex = try values.decode(String.self, forKey: .tintHex)
        density = values.contains(.density) ? try values.decode(FolderDensity.self, forKey: .density) : .standard
        backButtonStyle = values.contains(.backButtonStyle)
            ? try values.decode(FolderBackButtonStyle.self, forKey: .backButtonStyle) : .chevronUp
        spacing = try values.decodeIfPresent(Int.self, forKey: .spacing)
        margin = try values.decodeIfPresent(Int.self, forKey: .margin)
        titleColorHex = try values.decodeIfPresent(String.self, forKey: .titleColorHex)
        titleOutlineHex = try values.decodeIfPresent(String.self, forKey: .titleOutlineHex)
        titleOutlineWidth = values.contains(.titleOutlineWidth)
            ? try values.decode(SavedGroupTitleOutlineWidth.self, forKey: .titleOutlineWidth) : .thin
        guard isValid else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                   debugDescription: "Invalid saved group appearance"))
        }
        self = normalized
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(grid, forKey: .grid)
        try values.encode(showsTitles, forKey: .showsTitles)
        try values.encode(iconSize, forKey: .iconSize)
        try values.encode(plate, forKey: .plate)
        try values.encode(tintHex, forKey: .tintHex)
        // Preserve old appearance bytes and layout revisions at the default.
        if density != .standard { try values.encode(density, forKey: .density) }
        if backButtonStyle != .chevronUp { try values.encode(backButtonStyle, forKey: .backButtonStyle) }
        try values.encodeIfPresent(spacing, forKey: .spacing)
        try values.encodeIfPresent(margin, forKey: .margin)
        try values.encodeIfPresent(titleColorHex, forKey: .titleColorHex)
        try values.encodeIfPresent(titleOutlineHex, forKey: .titleOutlineHex)
        if titleOutlineWidth != .thin { try values.encode(titleOutlineWidth, forKey: .titleOutlineWidth) }
    }
}
