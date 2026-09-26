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
    /// Side length of one square cell, in points.
    public let iconSide: CGFloat
    /// Gap between cells, in points.
    public let spacing: CGFloat

    /// The size the whole grid occupies.
    public var size: CGSize {
        CGSize(
            width: iconSide * CGFloat(columns) + spacing * CGFloat(max(0, columns - 1)),
            height: iconSide * CGFloat(rows) + spacing * CGFloat(max(0, rows - 1))
        )
    }

    /// Fits `tileCount` icons into `available`, laying them out `columns` across.
    ///
    /// - Parameters:
    ///   - tileCount: how many tiles will be drawn. Determines the row count.
    ///   - columns: how many fit across, which the caller knows and this cannot
    ///     guess: a widget size fixes it, a preview derives it from the count.
    ///   - available: the space the grid may use, after any header.
    ///   - spacing: the gap to leave between cells.
    public init(tileCount: Int, columns: Int, in available: CGSize, spacing: CGFloat) {
        let columns = max(1, columns)
        let rows = max(1, (max(0, tileCount) + columns - 1) / columns)
        self.columns = columns
        self.rows = rows
        self.spacing = spacing

        let byWidth = (available.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let byHeight = (available.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
        // Never negative: a container smaller than its own spacing is a layout
        // bug, but returning a negative frame turns it into a crash.
        self.iconSide = max(0, min(byWidth, byHeight))
    }

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
