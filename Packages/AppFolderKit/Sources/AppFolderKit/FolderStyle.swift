import Foundation
import SwiftUI

/// The content plate behind a folder's icons. Automatic leaves the widget's
/// independent glass surface visible without requiring a global Clear Home
/// Screen appearance. Solid and gradient paint above that base.
/// The stored raw values remain stable across appearance changes.
public enum FolderPlate: String, Codable, Sendable, CaseIterable {
    /// Show the widget's glass surface without a custom content-layer fill.
    case automatic
    /// One flat colour, ``FolderTint``.
    case solid
    /// A two-stop gradient derived from ``FolderTint``.
    case gradient

    /// Preserve the stored default and the widget's independent glass surface.
    public static let `default`: FolderPlate = .automatic

    /// Whether this plate needs a colour to draw at all.
    ///
    /// The editor uses it to decide whether to show a colour picker — asking for
    /// a colour that nothing reads is how a settings screen teaches people to
    /// distrust it.
    public var usesTint: Bool {
        switch self {
        case .automatic: false
        case .solid, .gradient: true
        }
    }

    public var localizedName: String {
        switch self {
        case .automatic: "自动"
        case .solid: "纯色"
        case .gradient: "渐变"
        }
    }

    /// Describe what the appearance setting can control.
    public var localizedExplanation: String {
        switch self {
        case .automatic:
            "小组件使用独立玻璃底板，无需把整个主屏幕切换为透明外观。"
        case .solid:
            "用下面选的颜色铺满小组件底板。"
        case .gradient:
            "由下面选的颜色推出一层渐变，比纯色更有层次。"
        }
    }
}

/// A colour, stored as the `#RRGGBB` string the library file holds.
///
/// A value type rather than a `Color` because the thing being modelled is a
/// *string on disk*, not a view. `Folder.colorHex` has been a string since the
/// first commit and stays one — the schema is a contract with libraries already
/// written — so this type is the parsing layer between that string and a
/// drawable colour, in one place instead of three.
public struct FolderTint: Sendable, Equatable, Hashable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Parses `#RRGGBB`, or `RRGGBB`. Returns nil rather than guessing at
    /// malformed input — a half-parsed colour would be a plate the user never
    /// chose.
    public init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.utf8.count == 6,
              value.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              let rgb = UInt32(value, radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    /// The colour as the library stores it, uppercase and with the `#`.
    public var hex: String {
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// What a folder with no colour of its own uses once one is needed.
    ///
    /// Reachable in practice: a folder saved while the plate was automatic has an
    /// empty `colorHex`, and switching it to 纯色 has to produce *something*.
    /// ``FolderStyle/init(plate:tint:showsTitles:)`` substitutes this, so a plate
    /// is never invisible because a colour was missing.
    public static let defaultTint = FolderTint(red: 0.204, green: 0.471, blue: 0.965)

    /// Perceived brightness, 0–1.
    ///
    /// The plain weighted sum rather than a linearized one, because the question
    /// it answers is a design question — "would white text read on this?" — and
    /// the simple form answers it the way a palette picker does.
    public var luminance: Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    /// Whether the colour is light enough that text on it should be dark.
    public var isLight: Bool { luminance > 0.6 }

    /// Mixes towards another colour; `amount` 0 leaves this one alone, 1 returns
    /// the other.
    public func blended(with other: FolderTint, amount: Double) -> FolderTint {
        let t = min(max(amount, 0), 1)
        return FolderTint(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t
        )
    }

    public var color: Color { Color(red: red, green: green, blue: blue) }

    /// The two stops of the ``FolderPlate/gradient`` fill.
    ///
    /// Lightened first and darkened second, so the gradient always runs from the
    /// top-left to the bottom-right of the widget regardless of the hue chosen.
    /// The amounts are modest on purpose: the icons sit on top of this, and a
    /// gradient strong enough to notice on its own is strong enough to fight
    /// with app artwork.
    public var gradientStops: (FolderTint, FolderTint) {
        (blended(with: FolderTint(red: 1, green: 1, blue: 1), amount: 0.20),
         blended(with: FolderTint(red: 0, green: 0, blue: 0), amount: 0.30))
    }

    public var gradient: LinearGradient {
        let (start, end) = gradientStops
        return LinearGradient(
            colors: [start.color, end.color],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension FolderTint {
    /// The tint a `ColorPicker` handed back, as a value the library can store.
    public init(_ color: Color) {
        let resolved = color.resolve(in: EnvironmentValues())
        self.init(
            red: Double(resolved.red),
            green: Double(resolved.green),
            blue: Double(resolved.blue)
        )
    }
}

/// Everything about how a folder looks: the plate, the colour, the labels.
///
/// One type carrying all three, rather than three parameters threaded through
/// the widget, the editor and the row thumbnails, because the three have to be
/// decided together — the label colour depends on the plate, and the plate's
/// colour is what the labels have to stay legible against.
///
/// It used to have an `init(_ folder: Folder)` as its natural landing place, so
/// that nothing downstream of the model had to know how a folder stored its
/// appearance. The folder model and its editor are gone; the direct-launch
/// widget builds its style straight from the five settings the user configured
/// in the Edit Widget sheet.
public struct FolderStyle: Sendable, Equatable, Hashable {
    public var plate: FolderPlate
    public var tint: FolderTint
    /// Whether each icon carries its name underneath.
    ///
    /// Off by default and off in every library written before this existed. The
    /// widget draws no labels today — they were removed deliberately, because the
    /// artwork is the identity of a tile — so this is an opt-in, not a restored
    /// default.
    public var showsTitles: Bool
    /// How much of the grid goes to icons rather than to the gaps between them,
    /// 0…1. With explicit spacing or margin, it scales artwork inside fixed
    /// cells. See ``FolderGridMetrics/gapShare(forIconScale:)`` for automatic geometry.
    public var iconScale: Double
    /// Whether the small widget shows a 3 × 3 or a 2 × 2 grid. See ``FolderGrid``.
    public var grid: FolderGrid
    /// A larger-family density; small widgets continue to use `grid`.
    public var density: FolderDensity
    public var backButtonStyle: FolderBackButtonStyle
    public var spacing: Int?
    public var margin: Int?
    public var titleTint: FolderTint?
    public var titleOutlineTint: FolderTint?
    public var titleOutlineWidth: SavedGroupTitleOutlineWidth

    public init(
        plate: FolderPlate = .default,
        tint: FolderTint = .defaultTint,
        showsTitles: Bool = false,
        iconScale: Double = FolderGridMetrics.defaultIconScale,
        grid: FolderGrid = .default,
        density: FolderDensity = .standard,
        backButtonStyle: FolderBackButtonStyle = .chevronUp,
        spacing: Int? = nil,
        margin: Int? = nil,
        titleTint: FolderTint? = nil,
        titleOutlineTint: FolderTint? = nil,
        titleOutlineWidth: SavedGroupTitleOutlineWidth = .thin
    ) {
        self.plate = plate
        self.tint = tint
        self.showsTitles = showsTitles
        self.iconScale = iconScale
        self.grid = grid
        self.density = density
        self.backButtonStyle = backButtonStyle
        self.spacing = spacing
        self.margin = margin
        self.titleTint = titleTint
        self.titleOutlineTint = titleOutlineTint
        self.titleOutlineWidth = titleOutlineWidth
    }

    /// Use the automatic background and matching semantic labels for the default
    /// overflow panel. Solid and gradient content fills do not apply to that panel;
    /// its geometry, selected grid, and title visibility stay unchanged.
    public var usingSystemPlate: FolderStyle {
        var copy = self
        copy.plate = .automatic
        return copy
    }

    /// The fill a folder's plate is drawn with, or nil for ``FolderPlate/automatic``.
    ///
    /// One place decides, so the widget and the editor's preview cannot disagree
    /// about what a folder looks like — the same reason ``FolderGridMetrics``
    /// exists, applied to colour instead of geometry.
    public var plateFill: AnyShapeStyle? {
        switch plate {
        case .automatic: nil
        case .solid: AnyShapeStyle(tint.color)
        case .gradient: AnyShapeStyle(tint.gradient)
        }
    }

    /// The colour a tile's name is drawn in.
    ///
    /// Follows the plate rather than being fixed. On the system's plate a
    /// hierarchical secondary is right and adapts to light and dark; on a plate
    /// we painted it would be grey-on-colour, so the answer has to come from the
    /// colour's own brightness. Yellow and purple are both legal choices here and
    /// they need opposite text.
    public var titleStyle: AnyShapeStyle {
        switch plate {
        case .automatic: AnyShapeStyle(HierarchicalShapeStyle.secondary)
        case .solid, .gradient:
            AnyShapeStyle(tint.isLight ? Color.black.opacity(0.72) : Color.white.opacity(0.94))
        }
    }

    /// Only item names use a custom title color. Navigation glyphs, canvas
    /// placeholders and other chrome retain the existing `titleStyle`.
    public var labelStyle: AnyShapeStyle {
        if let titleTint { AnyShapeStyle(titleTint.color) }
        else { titleStyle }
    }

    /// A resolvable color for explicitly styled Core Text labels. The default
    /// SwiftUI Text branch continues to use the semantic `labelStyle` above.
    public var labelColor: Color {
        if let titleTint { return titleTint.color }
        switch plate {
        case .automatic: return .secondary
        case .solid, .gradient:
            return tint.isLight ? Color.black.opacity(0.72) : Color.white.opacity(0.94)
        }
    }
}
