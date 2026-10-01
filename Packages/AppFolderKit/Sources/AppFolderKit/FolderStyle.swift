import Foundation
import SwiftUI

/// How a folder's widget fills the plate its icons sit on.
///
/// Three cases, and the missing fourth is the interesting one. There is no
/// `transparent`, because an app cannot make a widget's plate see-through: the
/// plate is drawn by the system around a snapshot that was already composited
/// onto an opaque sheet. That was measured seven ways — four fills in the
/// widget's own content, three in `containerBackground` — and not one of them
/// let the wallpaper through. The numbers are in
/// `docs/research/04-实现笔记.md`.
///
/// So the honest set is these three, and ``automatic`` is the one that matters:
/// it declines to paint, which leaves the plate to the system. That is also the
/// whole of the reference product's glass story. WidgetLoft's Style picker is
/// Solid / Gradient / Transparent, its App Store copy says "Glass *look* or your
/// own color", and its "Transparent" is the same thing as this case. Nothing has
/// to be switched on, cropped or enabled; a widget that paints nothing gets
/// whatever the system puts there, at whatever 图标外观 (默认 / 浅色 / 深色 /
/// 透明) the user has chosen.
///
/// What the app *cannot* do is make a plate of its own see-through, and an
/// earlier version of this comment overstated that into "you have to go and
/// switch the system to 透明", which the user rightly pushed back on. The
/// distinction that survives measurement: we choose between *the system's
/// plate* and *one we paint*, not between opaque and transparent.
///
/// The UI name and the stored name have drifted apart on purpose. On disk this
/// case is still `automatic`, because that is what libraries already written
/// hold; in the picker it reads 透明, because that is what the reference product
/// calls the same option and a user comparing the two pickers should not have to
/// work out that they are the same thing.
public enum FolderPlate: String, Codable, Sendable, CaseIterable {
    /// Draw nothing and let the system put its own plate under the widget.
    ///
    /// This is the only arrangement that reacts to the user's 图标外观 setting at
    /// all — including the 透明 one, where the system drops the plate and the
    /// wallpaper shows through.
    case automatic
    /// One flat colour, ``FolderTint``.
    case solid
    /// A two-stop gradient derived from ``FolderTint``.
    case gradient

    /// What a folder draws when the user has not chosen anything.
    ///
    /// Not a colour, deliberately: the app shipped with no plate of its own for
    /// its whole life before this enum, and matching that keeps a library that
    /// was written before the field existed rendering exactly as it did.
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
        case .automatic: "透明"
        case .solid: "纯色"
        case .gradient: "渐变"
        }
    }

    /// A one-line explanation for the editor, in the same spirit as
    /// ``LaunchStrategy/localizedExplanation``: a setting the user cannot see the
    /// effect of from inside the app has to say what it will do.
    ///
    /// Written from measurements, not from the API's names. An earlier draft
    /// promised that the system's plate "本身就是液态玻璃，会跟着壁纸变"; a
    /// screenshot of three widgets on one Home Screen does not support that —
    /// Apple's own Maps and Calendar widgets measure the same flat `#FFFFFF` ours
    /// does, while the iOS folders and the Dock beside them transmit. So this
    /// says what the app does (paints nothing), what that gets the user (the
    /// system's treatment, at whatever 图标外观 they chose), and what the app
    /// cannot do (paint its own see-through plate), without promising a material
    /// it does not control.
    public var localizedExplanation: String {
        switch self {
        case .automatic:
            "不自己画底板，整块交给系统。桌面上那块板是系统画的，跟着「图标外观」（默认 / 浅色 / 深色 / 透明）走——切到透明档时它会被撤掉，壁纸就透出来了。App 自己画的半透明色做不到这件事：它会被系统先合到那块板上，合出来是一块灰。"
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
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return nil }
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
    /// Reachable in practice: a folder saved while the plate was 透明 has an
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
/// colour is what the labels have to stay legible against. It is also the
/// natural place for ``init(_:)`` to land, so nothing downstream of the model
/// has to know how a `Folder` stores its appearance.
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
    /// 0…1. See ``FolderGridMetrics/gapShare(forIconScale:)``.
    public var iconScale: Double
    /// Whether the small widget shows a 3 × 3 or a 2 × 2 grid. See ``FolderGrid``.
    public var grid: FolderGrid

    public init(
        plate: FolderPlate = .default,
        tint: FolderTint = .defaultTint,
        showsTitles: Bool = false,
        iconScale: Double = FolderGridMetrics.defaultIconScale,
        grid: FolderGrid = .default
    ) {
        self.plate = plate
        self.tint = tint
        self.showsTitles = showsTitles
        self.iconScale = iconScale
        self.grid = grid
    }

    /// The appearance a folder asked for, with the missing pieces filled in.
    public init(_ folder: Folder) {
        self.init(
            plate: folder.plate,
            tint: FolderTint(hex: folder.colorHex) ?? .defaultTint,
            showsTitles: folder.showsTitles,
            iconScale: folder.iconScale,
            grid: folder.grid
        )
    }

    /// Whether the system is allowed to drop the plate.
    ///
    /// Always true, and it is worth writing down why it is not a function of
    /// ``plate``, which is what it looks like it should be. The switch that
    /// grants this, `containerBackgroundRemovable`, is a method on
    /// **`WidgetConfiguration`** — it is applied once to the widget, not per
    /// timeline entry — so a folder cannot decide it. See the call site in
    /// `AppFolderWidget.swift` for what that does and does not cost.
    ///
    /// The reason to grant it at all is ``FolderPlate/automatic``: Apple's words
    /// are that marking the container removable lets the system drop it "to
    /// allow people to place the widget in as many contexts as possible", and
    /// that without the mark "the system always displays the background
    /// container". A plate nobody chose should be droppable; that is the whole
    /// design.
    public static let isPlateRemovableToSystem = true

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
}
