import CoreGraphics

/// How the mini-grid inside the overflow cell is divided up.
///
/// ## What this cell is
///
/// The last cell of a folder that does not fit is not a button — it is a
/// *folder*, drawn the way iOS and Android draw one: a few miniature icons with
/// a count. The cell already did this; what it did not do is decide how many
/// miniatures to draw from the space it has. That decision is this type, and it
/// lives in the shared package because **two views draw this cell and neither
/// can import the other** — the widget's ``NestedTileButton`` and the editor
/// preview's `NestedCellView`. Before this, each carried its own copy of the
/// mini size and gap, kept honest only by a comment asking the next person to
/// change both.
///
/// ## Why a ladder rather than one density
///
/// The cell is drawn at about 37 pt in a small widget and about 80 pt in a
/// large one. A fixed 2 × 2 leaves the larger cell almost empty — four miniatures
/// floating in space with room for nine — and a fixed 3 × 3 is mush in the
/// smaller one. So the density follows the space.
///
/// The number of columns is not chosen by what "looks about right" at each size.
/// It is chosen by a single constraint: a miniature below ``minimumMiniSide``
/// stops reading as an app icon and becomes a speck of colour, so a row count is
/// only allowed when the miniatures would *still* be at least that big. The
/// threshold below is that number, and the resulting sizes fall out of it.
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
    /// will be — the editor builds its `NestedCell` from the folder long before it
    /// has a frame — so it can hand over a list and let the view slice it. Bounded
    /// at nine rather than at ``maximumColumns`` squared, because nine is the cap
    /// and the two must not drift.
    public static let maximumCapacity = maximumColumns * maximumColumns

    /// The largest grid drawn, at any size.
    ///
    /// Nine, and deliberately not more. Four by four *fits* in a large widget —
    /// sixteen miniatures at about 16 pt each — but the count is not what is
    /// scarce here. A preview's job is to say "this is a folder with things in
    /// it", which nine icons do and sixteen do not: past a certain count the
    /// block stops reading as a set of apps and starts reading as texture, and
    /// the count badge beside it already carries the exact number. Nine is also
    /// what iOS and Android draw for a folder, so the cell is recognisable as one
    /// rather than as a new idea.
    public static let maximumColumns = 3

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
    /// cell's rounded corner and the count badge need. The block's badge hangs off
    /// its bottom-trailing corner, so a block that reached the cell's edges would
    /// put the count under the badge and the outermost miniatures into the corner
    /// radius.
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