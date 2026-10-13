import CoreGraphics

/// How the mini-grid inside the overflow cell is divided up.
///
/// ## What this cell is
///
/// The last cell of a grid that does not fit is not a button — it is a *folder*,
/// drawn the way iOS draws one: a few miniature icons. This type decides how many
/// miniatures that glyph shows and how big they are.
///
/// ## Why 2 × 2, at every size
///
/// This used to be a ladder — 2 × 2 in a small cell, 3 × 3 once the cell passed
/// about 50 pt — on the reasoning that a bigger cell holding only four miniatures
/// looks empty. Against the real thing the ladder does the opposite of what it
/// promised: it draws the **same folder glyph two different ways side by side on
/// one Home Screen**. The two small-widget grids are the clearest case. A 九宫格
/// door cell is about 37 pt and landed on 2 × 2; a 四宫格 door cell is about 61 pt
/// and crossed the threshold into 3 × 3 — so the two "其他" cells, which mean the
/// same thing, did not look like the same thing.
///
/// So the glyph is fixed at 2 × 2 — four miniatures, what iOS draws for a folder —
/// and only the *size* of a miniature follows the cell. The count of hidden apps
/// is the badge's job, not the glyph's; a preview's job is to say "there is a
/// folder here", and four does that at every size without turning into texture.
///
/// The miniature size is not chosen by eye either. It follows from ``fillShare``,
/// which bounds the block so the outer miniatures clear the cell's corner radius,
/// and from ``minimumMiniSide``, the floor below which a miniature stops reading
/// as an app icon. A cell too small to hold two rows at the floor draws one.
public struct MiniGridDensity: Sendable, Equatable {
    /// How many miniatures across, and down — the grid is square.
    public let columns: Int

    /// One miniature's side, in the same points as the cell it sits in.
    public let miniSide: CGFloat

    /// The gap between two miniatures, and between the block and the cell's edge.
    public let spacing: CGFloat

    /// How many miniatures this density draws. The caller supplies at most this
    /// many previews; see ``maximumCapacity`` for a bound that does not depend on
    /// a size.
    public var capacity: Int { columns * columns }

    public var rows: Int { columns }

    /// The most miniatures any density draws.
    ///
    /// For a caller that has to *gather* previews before it knows how big the cell
    /// will be, so it can hand over a list and let the view slice it. Four, because
    /// ``maximumColumns`` is two and the two must not drift.
    public static let maximumCapacity = maximumColumns * maximumColumns

    /// How many miniatures across the glyph draws: two, always.
    ///
    /// Not a tuning knob. Two is what iOS draws for a folder, and it is what keeps
    /// the door identical whether it sits in a 九宫格 cell (about 37 pt) or a 四宫格
    /// one (about 61 pt) — a ladder made exactly those two the same cell drawn
    /// 2 × 2 and 3 × 3. See the type's discussion.
    public static let maximumColumns = 2

    /// The smallest a miniature may be, in points, and the number the whole
    /// ladder is derived from.
    ///
    /// Not a preference — it is the size below which the artwork of a third-party
    /// app icon no longer reads as that app. It happens to sit just under what a
    /// 2 × 2 already produced in the smallest cell (about 10.4 pt), so the
    /// existing look is the floor rather than something the change has to clear.
    public static let minimumMiniSide: CGFloat = 9

    /// The gap as a share of a miniature's side.
    ///
    /// Exactly the ratio the old hard-coded constants used — a 0.08 gap against a
    /// 0.28 miniature — restated as one number so the two views cannot disagree.
    /// It is applied to the *miniature* rather than to the cell so that the gap
    /// tightens with the icons, which is what keeps a denser grid from turning
    /// into a lattice of gaps.
    public static let spacingShare: CGFloat = 0.08 / 0.28

    /// How much of the cell the miniatures are allowed to occupy.
    ///
    /// A little under two thirds, and this is not slack — it is the room the
    /// cell's rounded corner needs: a block that reached the cell's edges would
    /// push the outermost miniatures into the corner radius.
    ///
    /// A filled cell was tried once and rejected for a second reason: at 2 × 2 it
    /// reads as one blurry rectangle rather than as four apps. So the block stays
    /// inset, and at the old density this constant is what reproduces the old
    /// numbers exactly: 0.64 of a cell, split 2 × 2 with a 2/7 gap, gives a
    /// 0.28-of-cell miniature — the share that was hard-coded before.
    public static let fillShare: CGFloat = 0.64

    public init(cellSide: CGFloat) {
        let side = max(0, cellSide)
        let columns = Self.columns(fitting: side)
        // Solved rather than scaled, within the block the fill share defines: the
        // miniatures and the gaps between them have to add up to the block
        // exactly, so `n * m + (n - 1) * m * share = side * fill` rearranges to
        // this. Scaling a fixed size instead would leave the block short of its
        // allowance at some sizes and over it at others.
        let divisor = CGFloat(columns) + CGFloat(columns - 1) * Self.spacingShare
        let miniSide = side * Self.fillShare / divisor

        self.columns = columns
        self.miniSide = miniSide
        self.spacing = miniSide * Self.spacingShare
    }

    /// The widest grid that still clears ``minimumMiniSide`` in this cell.
    ///
    /// Walked down rather than computed, because the constraint is a floor on the
    /// *resulting* size and the result is what is being chosen. Two or three
    /// steps, so there is nothing to gain from a closed form, and this way the
    /// floor stays the stated rule rather than something a reader has to
    /// re-derive from it.
    private static func columns(fitting cellSide: CGFloat) -> Int {
        for columns in stride(from: maximumColumns, through: 1, by: -1)
        where requiredSide(forColumns: columns) <= cellSide {
            return columns
        }
        return 1
    }

    /// The cell side a grid of this many columns needs to hold miniatures of
    /// exactly ``minimumMiniSide``.
    ///
    /// The inverse of the solve in ``init(cellSide:)``, and the reason the
    /// densities come out at the sizes they do: a 3 × 3 appears at 50.2 pt, not
    /// at a number someone picked. Exposed as `internal` so the tests can assert
    /// the ladder against the floor instead of against hard-coded thresholds.
    static func requiredSide(forColumns columns: Int) -> CGFloat {
        guard columns > 1 else { return minimumMiniSide / fillShare }
        return minimumMiniSide * (CGFloat(columns) + CGFloat(columns - 1) * spacingShare) / fillShare
    }
}
