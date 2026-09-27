import CoreGraphics

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
    public init(
        tileCount: Int,
        columns: Int,
        in available: CGSize,
        showsTitles: Bool = false
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
        self.spacing = max(2, available.width / 12)

        let byWidth = (available.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let byHeight = (available.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
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
