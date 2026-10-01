import CoreGraphics
import WidgetKit

/// Where the icons in a folder grid go.
///
/// Shared between the widget and the app's preview, because "what the widget
/// will look like" is the only thing the preview is for. Two independent layout
/// calculations would drift, and the drift would be invisible until a user
/// complained that the preview lied to them.
///
/// The cell is square and the tighter of the two constraints wins, so a wide
/// short widget does not stretch its icons into ovals and a tall one leaves its
/// slack at the bottom rather than squeezing every icon sideways.
public struct FolderGridMetrics: Sendable, Equatable {
    /// How many icons fit across.
    public let columns: Int
    /// How many rows are needed for the tiles given.
    public let rows: Int
    /// Side length of one square icon, in points.
    public let iconSide: CGFloat
    /// Gap between cells, in points.
    public let spacing: CGFloat

    /// The outer margin the grid leaves on every side, in points.
    ///
    /// Derived rather than passed in, and derived *from the container it was
    /// given*, which is the widget's width less this margin on both sides —
    /// hence the division below rather than a straight multiplication. Callers
    /// hand the grid the same inset container they always did; how much of the
    /// widget that leaves unused is this type's decision now, not theirs.
    public let margin: CGFloat
    /// Whether each icon carries its name underneath.
    public let showsTitles: Bool

    /// Vertical space one name takes under its icon, in points; 0 when titles
    /// are off.
    ///
    /// A share of the cell rather than a fixed number of points, so it scales
    /// with the widget. A fixed height would be generous in a Small widget and
    /// cramped in a Large one, and the two are drawn by the same code.
    public let labelHeight: CGFloat

    /// Icon plus its name — the height one row of cells occupies.
    public var cellHeight: CGFloat { iconSide + labelHeight }

    /// The size the whole grid occupies.
    public var size: CGSize {
        CGSize(
            width: iconSide * CGFloat(columns) + spacing * CGFloat(max(0, columns - 1)),
            height: cellHeight * CGFloat(rows) + spacing * CGFloat(max(0, rows - 1))
        )
    }

    /// Font size for a tile's name, derived from the room reserved for it.
    ///
    /// Here rather than in either view because the widget and the preview must
    /// agree on it: a name that fits in the editor and is clipped on the Home
    /// Screen is the drift this whole type exists to prevent.
    public var titleFontSize: CGFloat {
        guard showsTitles else { return 0 }
        return max(7, labelHeight * 0.78)
    }

    /// Gap between an icon and its name.
    public var titleSpacing: CGFloat {
        guard showsTitles else { return 0 }
        return max(1, labelHeight * 0.15)
    }

    /// What fraction of a cell a name is allowed to take when titles are on.
    private static let labelShare: CGFloat = 0.26

    /// The gap between cells at ``FolderGridMetrics/standardGapShare``, as a
    /// share of the grid's width.
    ///
    /// This is the value the type has always used — it was written inline as
    /// `available.width / 12`. It is named now because ``iconScale`` moves it and
    /// the name is what makes "0.5 means unchanged" checkable rather than a
    /// claim.
    public static let standardGapShare: CGFloat = 1.0 / 12.0

    /// Where the gap goes as ``iconScale`` runs from 0 to 1.
    ///
    /// The gap is the only lever on icon size, and it is the only one that needs
    /// to exist: the outer margin is not spare room. It is what keeps the corner
    /// cells clear of the widget's own corner radius — measured at 27.7 pt — so
    /// spending it on bigger icons would clip the artwork the user is trying to
    /// enlarge. The cells either side of a gap, by contrast, are ours to divide
    /// up: cells and gaps together always add up to the grid's width, so no
    /// amount of sliding this can change how many fit.
    ///
    /// The lower half moves slower than the upper half. Below the standard gap
    /// the icons are shrinking and there is slack around the grid anyway, so the
    /// control has little to do; above it, every point goes straight into the
    /// icons, which is the direction a user reaching for this usually wants.
    ///
    /// - Returns: the gap as a share of the grid's width: 0.15 at scale 0 and
    ///   ``standardGapShare`` at 0.5, falling to 0 at 1. In practice the floor
    ///   in the initialiser holds the top end at 2 pt, so icons at the maximum
    ///   setting sit close together without touching.
    static func gapShare(forIconScale scale: Double) -> CGFloat {
        let scale = CGFloat(min(max(scale, 0), 1))
        if scale <= 0.5 {
            let t = scale / 0.5
            return Self.standardGapShare * (1 + 0.8 * (1 - t))
        }
        let t = (scale - 0.5) / 0.5
        return Self.standardGapShare * (1 - t)
    }

    /// The outer margin the grid leaves at ``FolderGridMetrics/standardMarginShare``,
    /// as a share of the widget's width.
    ///
    /// 18 pt of a 170 pt Small widget, which is the system's own content margin
    /// and what this type used to be handed already-inset by, so naming the
    /// share changes no layout — see ``defaultIconScale``.
    public static let standardMarginShare: CGFloat = 18.0 / 170.0

    /// Where the outer margin goes as ``iconScale`` runs from 0 to 1.
    ///
    /// The margin is a second lever on icon size, and a bigger one than the gap:
    /// at the top of the range it gives the icons about 3% of the widget's width
    /// per side on top of everything the gap can offer.
    ///
    /// It is not free, but it is far cheaper than it looks. The widget clips its
    /// content to a rounded rect of radius ~27.7 pt, so the question is whether
    /// a corner icon's own corner survives that clip. The icon is already a
    /// rounded rect of radius `side * 0.22`, so its outermost point on the
    /// diagonal sits `0.29 * radius` inside the cell corner, and the requirement
    /// `margin + 0.293 * iconRadius >= 8.11` falls out of the two arcs meeting.
    /// For a full nine-cell grid that resolves to a margin of about **4.8 pt** —
    /// not 18 pt. What the 18 pt margin buys is not safety for the icons at all:
    /// it is that a *painted plate* fills the widget edge to edge without its own
    /// corners showing a seam against the system's clip.
    ///
    /// 0.035 is that 4.8 pt bound with room to spare, expressed as a share of the
    /// Small widget so it scales to the other families.
    ///
    /// - Returns: the margin as a share of the widget's width: 0.135 at scale 0,
    ///   ``standardMarginShare`` at 0.5, 0.035 at 1.
    static func marginShare(forIconScale scale: Double) -> CGFloat {
        let scale = CGFloat(min(max(scale, 0), 1))
        let widest: CGFloat = 0.135
        let tightest: CGFloat = 0.035
        if scale <= 0.5 {
            let t = scale / 0.5
            return Self.standardMarginShare + (widest - Self.standardMarginShare) * (1 - t)
        }
        let t = (scale - 0.5) / 0.5
        return Self.standardMarginShare + (tightest - Self.standardMarginShare) * t
    }

    /// The icon-size setting a folder that has never been given one uses, and
    /// therefore the one every library written before this existed decodes to.
    ///
    /// It is the midpoint because ``gapShare(forIconScale:)`` is defined to
    /// return the standard gap there — the arrangement those libraries were
    /// already being drawn at. A default of 0 or 1 would have silently resized
    /// every folder on the Home Screen the first time this shipped.
    public static let defaultIconScale: Double = 0.5

    /// Fits `tileCount` icons into `available`, laying them out `columns` across.
    ///
    /// - Parameters:
    ///   - tileCount: how many tiles will be drawn. Determines the row count.
    ///   - columns: how many fit across, which the caller knows and this cannot
    ///     guess: a widget size fixes it, a preview derives it from the count.
    ///   - available: the space the grid may use, after any header. Pass an
    ///     unbounded height for a width-driven layout, which is what a preview
    ///     inside an `aspectRatio` is.
    ///   - showsTitles: whether each icon needs room for its name beneath it.
    ///   - iconScale: how much of the grid should go to icons rather than to the
    ///     gaps between them. See ``gapShare(forIconScale:)``; the default is
    ///     ``defaultIconScale``, which is the standard gap.
    public init(
        tileCount: Int,
        columns: Int,
        in available: CGSize,
        showsTitles: Bool = false,
        iconScale: Double = FolderGridMetrics.defaultIconScale
    ) {
        let columns = max(1, columns)
        let rows = max(1, (max(0, tileCount) + columns - 1) / columns)
        self.columns = columns
        self.rows = rows
        self.showsTitles = showsTitles

        // Derived here rather than taken from the caller. The widget and the
        // editor's preview both used to work it out for themselves and they had
        // drifted to 0.083 and 0.055 of the container — so the preview, whose
        // only job is to say what the widget will look like, showed a visibly
        // tighter grid than the widget drew.
        //
        // The floor of 2 pt is what stops `iconScale` from squeezing the gap
        // shut entirely at the top of its range. It is the same bound the
        // module has always carried, and at this size it is what keeps a
        // maximum-setting grid from drawing its icons edge to edge: 2 pt of a
        // 134 pt container is about 1.5% of the cell.
        //
        // It also decides where the setting stops having an effect. For a
        // nine-cell Small widget the floor is reached just past 0.8, so the last
        // fifth of the slider's travel does nothing — the footnote in the editor
        // quotes the computed size rather than the slider's value for exactly
        // that reason.
        // `available` is the whole widget, not a pre-inset part of it: the margin
        // is taken off here so that one number — the size setting — decides both
        // how much of the widget goes to the outer border and how much to the
        // gaps, rather than an inset being applied by every caller and this type
        // only owning what is left.
        let marginShare = Self.marginShare(forIconScale: iconScale)
        self.margin = available.width * marginShare

        // What is left for the cells and the gaps between them. Never negative:
        // a container smaller than its own margin is a layout bug, but a
        // negative frame turns it into a crash.
        let inner = CGSize(
            width: max(0, available.width - 2 * self.margin),
            height: max(0, available.height - 2 * self.margin)
        )

        self.spacing = max(2, inner.width * Self.gapShare(forIconScale: iconScale))

        let byWidth = (inner.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let byHeight = (inner.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
        // Never negative: a container smaller than its own spacing is a layout
        // bug, but returning a negative frame turns it into a crash.
        let cell = max(0, min(byWidth, byHeight))

        // The name comes out of the cell's height, not out of the widget's
        // slack. Taking it from slack would work only where there is slack, and
        // a full 3×3 grid has none — the icons would keep their size and the
        // names would fall off the bottom.
        let reserved = showsTitles ? cell * Self.labelShare : 0
        self.iconSide = max(0, cell - reserved)
        self.labelHeight = reserved
    }

    /// The corner radius of an icon in this grid.
    ///
    /// Here for the same reason as everything else on this type. The widget drew
    /// a fixed 8 pt and the preview drew `side * 0.22`, so a 3×3 grid was making
    /// two different shapes of the same artwork depending on where you looked.
    public var cornerRadius: CGFloat { iconSide * 0.22 }

    /// The column count a folder of this size reads best at.
    ///
    /// 1–4 tiles → 2 columns, 5–9 → 3 (the classic 大文件夹 square), 10+ → 4,
    /// which is only reachable in the Extra Large widget.
    public static func columns(forTileCount count: Int) -> Int {
        switch count {
        case 0...4: 2
        case 5...9: 3
        default: 4
        }
    }
}

/// How many icons a folder puts across, which is the one thing the grid's shape
/// is not free to decide on its own.
///
/// The timeline provider truncates a folder to this many cells and the widget
/// view lays the tiles out in this many columns, so the two read the same value
/// by construction. They were written separately once — a capacity of 4 for a
/// small widget next to a hard-coded 2 columns — and the drift was invisible
/// until a folder of nine apps quietly showed four.
///
/// Named for what the user sees rather than for the column count, because it is
/// a user-facing choice: 九宫格 is the classic 大文件夹 square, 四宫格 trades five
/// apps for icons large enough to match a real Home Screen icon.
public enum FolderGrid: String, Codable, Sendable, CaseIterable {
    /// 3 × 3, the arrangement that holds nine apps.
    case nine
    /// 2 × 2, for a folder of four shown at close to full size.
    case four

    /// The arrangement a folder that has never been given one uses, and so the
    /// one every library written before this existed decodes to.
    ///
    /// `nine`, because that is what the small widget already drew and what the
    /// 大文件夹 idea is — an existing folder must not lose five apps to a
    /// setting its owner never made.
    public static let `default`: FolderGrid = .nine

    public var localizedName: String {
        switch self {
        case .nine: "九宫格"
        case .four: "四宫格"
        }
    }

    /// A one-line explanation for the editor, in the same spirit as
    /// ``FolderPlate/localizedExplanation``: a setting whose effect is only
    /// visible on the Home Screen has to say what it will do.
    ///
    /// Both sentences end on the number of apps, because that is the actual
    /// trade and the icon size is what buys it. The sizes quoted are for the
    /// small widget at the default icon-size setting.
    public var localizedExplanation: String {
        switch self {
        case .nine:
            "3 × 3，放 9 个 App，图标约 37pt。只影响 2×2 的小组件；中大尺寸保持 3 列。"
        case .four:
            "2 × 2，放 4 个 App，图标约 60pt——和系统桌面图标一样大。多出来的 App 会留在文件夹里，切回九宫格就能看到。"
        }
    }

    /// How many icons across, in a widget of the given size.
    ///
    /// The choice only reaches the small widget. Medium and large keep their own
    /// column counts because a 2 × 2 grid in a wide widget would waste most of
    /// the width for no benefit — the icons there are already full size, so 四宫格
    /// would buy nothing and cost two apps.
    public func columns(for family: WidgetFamily) -> Int {
        switch (self, family) {
        case (.four, .systemSmall):
            return 2
        case (_, .systemSmall):
            return 3
        case (_, .systemMedium):
            return 3
        case (_, .systemLarge):
            return 3
        case (_, .systemExtraLarge), (_, .systemExtraLargePortrait):
            return 4
        default:
            return 3
        }
    }

    /// How many tiles fit, which is also this grid's cell count: the grid is
    /// always full, so an empty cell would be reserving a slot for nothing.
    public func capacity(for family: WidgetFamily) -> Int {
        let columns = columns(for: family)
        // Rows per family, so the grid is a rectangle that fills the widget
        // rather than a square that leaves the bottom third bare.
        let rows: Int
        switch family {
        case .systemSmall: rows = columns          // square widget, square grid
        case .systemMedium, .systemLarge: rows = 3
        case .systemExtraLarge, .systemExtraLargePortrait: rows = 3
        default: rows = columns
        }
        return columns * rows
    }
}

public extension WidgetFamily {
    /// How many tiles this family has room for at the default grid.
    var gridCapacity: Int { FolderGrid.default.capacity(for: self) }

    /// How many icons this family draws across at the default grid.
    var gridColumns: Int { FolderGrid.default.columns(for: self) }
}
