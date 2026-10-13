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

    /// The tightest the gap may become, as a share of the grid's width.
    ///
    /// ## Why this is a share and no longer a fixed 2 pt
    ///
    /// The gap used to bottom out at `max(2, …)` points, and at the top of the
    /// size range that is where it landed — so the largest setting drew a
    /// nine-cell grid with 2 pt between cells against 51.4 pt icons, a ratio of
    /// **3.9%**. Measured on a real Home Screen, that does not read as a grid with
    /// small gaps; it reads as one solid block with faint seams, and the user's
    /// report was exactly that: 大 has "几乎没有间隔".
    ///
    /// A fixed floor cannot express "still visibly separated" at every size,
    /// because the thing it has to be visible *against* — the cell — scales with
    /// the widget. A share can: at this value the same nine-cell Small grid draws
    /// 5.0 pt gaps against 49.4 pt icons, a ratio of 10.1%.
    ///
    /// ## What it costs, and why that is the honest trade
    ///
    /// Cells and gaps together are exactly the grid's inner width, so a wider gap
    /// has to come out of the icons: 51.4 pt becomes 48.3 pt, a 6% loss. There is
    /// no arrangement that keeps both — the constraint is arithmetic, not policy.
    /// What the share buys is that the loss is *proportional* rather than absolute,
    /// so it stays 6% instead of growing into the whole gap as the widget shrinks.
    ///
    /// ## Why exactly half the standard, and where it starts to bite
    ///
    /// Because ``gapShare(forIconScale:)`` is *already* at half the standard gap
    /// when it reaches 中: the curve is defined to fall from the standard at 0.5 to
    /// zero at 1, so at 0.75 it is exactly ``standardGapShare`` / 2. Setting the
    /// floor there means the curve's own value governs at 中 and below — nothing
    /// moves — and above 中 the gap simply holds.
    ///
    /// So the rule the user is actually operating is: **the gap may halve at most,
    /// and it has already halved by 中.** Past that, the size setting moves only the
    /// margin, which is what makes 大 read as "the same clarity with bigger icons"
    /// rather than as "the same grid squeezed shut". The measured ratios at the top
    /// of the range become 13.6% for a nine-cell grid and 8.7% for a four-cell one,
    /// against 3.9% and 2.6% before.
    ///
    /// Anything larger than this would bind at 中 and resize the arrangement the
    /// pre-slider layout drew — the 37.2 pt icon and 11.2 pt gap ``WidgetGridTests``
    /// pins. So this is not a tuning knob chosen by eye; it is the largest value
    /// that leaves that pinned arrangement alone.
    /// Spelled as a literal rather than as `standardGapShare / 2`, though it is
    /// exactly that. A `static let` reading another `static let` is a lazy global
    /// initialized on first touch, and while Swift does order that correctly within
    /// a type, the failure mode if it ever did not is this value reading `0` —
    /// which would draw every grid at the top of the range with no gap at all,
    /// i.e. exactly the bug this constant exists to prevent. The two are kept in
    /// step by the test below rather than by one being defined from the other.
    public static let minimumGapShare: CGFloat = 1.0 / 24.0

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
    ///   ``standardGapShare`` at 0.5, falling toward 0 at 1 — where
    ///   ``minimumGapShare`` takes over, so the curve's own value is only used
    ///   above that floor.
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

    /// How little of the widget the outer margin may take, as a share of its
    /// width — the far end of ``marginShare(forIconScale:)``, named so
    /// ``legibleMarginShare(in:columns:rows:showsTitles:iconScale:)`` can clamp to
    /// it rather than restate 0.035 and drift from this one.
    static let tightestMarginShare: CGFloat = 0.035

    /// The smallest an icon may be drawn, in points, whatever the size setting
    /// asks for.
    ///
    /// The number ``DirectLaunchMetricsTests`` asserts, made part of the layout so
    /// that assertion is a guarantee rather than a hope. 28 pt is about the small
    /// widget's own icon at the default setting: below it an icon stops being
    /// recognisable and stops being a comfortable tap target.
    public static let legibilityFloor: CGFloat = 28

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
        let tightest = Self.tightestMarginShare
        if scale <= 0.5 {
            let t = scale / 0.5
            return Self.standardMarginShare + (widest - Self.standardMarginShare) * (1 - t)
        }
        let t = (scale - 0.5) / 0.5
        return Self.standardMarginShare + (tightest - Self.standardMarginShare) * t
    }

    /// The margin this grid may actually afford, which is never more than the
    /// size setting asked for.
    ///
    /// ## Why the sharing rule needs a floor
    ///
    /// ``marginShare(forIconScale:)`` is a share of the widget's **width**, and on
    /// a wide, short widget that is the wrong axis to spend. A medium widget is
    /// 349 × 166: at the standard share the margin is 37 pt *top and bottom*,
    /// leaving 92 pt for three rows. The size setting is the only thing that
    /// pulls it back, so a user who wants smaller icons — 小, which is the setting
    /// someone with a crowded grid reaches for — gets the *largest* margin the
    /// range ever draws and the *smallest* icons, which is backwards. Measured: a
    /// nine-slot medium grid at 小 came out **11.4 pt**, the same number the
    /// hard-coded 18 pt inset used to produce, and at 中 — the shipping default —
    /// **22.7 pt**. Both are unreadable, and both were hidden by a test that only
    /// ran at 大.
    ///
    /// The floor is what makes the settings describe the icons rather than the
    /// border: whichever margin the asked-for share implies, the grid keeps
    /// whichever is *smaller* of that and the largest margin whose cells still
    /// clear ``legibilityFloor``. The size setting can then only ever tighten the
    /// margin; it can never push the icons under the floor.
    ///
    /// ## Why the margin and not the gap
    ///
    /// ``minimumGapShare`` documents this from the other side: the margin is not
    /// spare room, and it is `margin + 0.293 * iconRadius >= 8.11` that keeps a
    /// corner icon clear of the system's clip — about 4.8 pt for a full nine-cell
    /// grid. So the margin has a hard floor of its own, ``tightestMarginShare``,
    /// and this clamp never goes below it. What it does below that point is let
    /// the grid draw smaller cells inside a margin it cannot shrink further, which
    /// is the honest outcome: the widget really is too small for three rows of 28 pt
    /// icons, and drawing them anyway is better than drawing them at 11 pt.
    ///
    /// ## Why it is a search and not a formula
    ///
    /// The cell size depends on the margin and the legible margin depends on the
    /// cell size, so there is no closed form. Both branches of
    /// ``init(tileCount:columns:in:showsTitles:iconScale:)`` call this, and
    /// ``cell(in:columns:rows:gapShare:marginShare:)`` is the probe it searches
    /// with, so the answer the layout uses and the answer a caller can reproduce
    /// are the same number by construction.
    ///
    /// ## What the search promises, and what it does not
    ///
    /// It promises a **feasible** answer: it only ever returns a margin the probe
    /// accepted, or — when even ``tightestMarginShare`` is not enough for this many
    /// rows — that tightest margin, which is a floor rather than a failure. A
    /// caller can rely on "if the floor was reachable, the icon clears it".
    ///
    /// It does not promise the *largest* such margin, and the reason is worth
    /// stating because a reader will assume it does. Bisection assumes the icon grows
    /// as the margin shrinks, and that is very nearly true but not exactly: the gap
    /// is measured against the smaller inner dimension, so on a wide short widget
    /// with many columns the binding axis can cross over partway down the range and
    /// the cell can tick down as the margin ticks down by a hair. The range where
    /// this bites sits below the floor anyway — the cells there are already too
    /// small to matter — and the cost of a non-exact answer is a fraction of a point
    /// of border. Tightening this would mean scanning the range instead of bisecting
    /// it, on the render path, for a difference the eye cannot see.
    static func legibleMarginShare(
        in available: CGSize,
        columns: Int,
        rows: Int,
        showsTitles: Bool,
        iconScale: Double
    ) -> CGFloat {
        let share = marginShare(forIconScale: iconScale)
        let lowest = Self.tightestMarginShare
        func iconSide(at marginShare: CGFloat) -> CGFloat {
            let cell = Self.cell(
                in: available, columns: columns, rows: rows,
                gapShare: Self.gapShare(forIconScale: iconScale),
                marginShare: marginShare
            )
            // The name comes out of the icon, exactly as it does in `init` — so the
            // search cannot call an arrangement legible that the layout then draws
            // small enough to be unreadable.
            return showsTitles ? cell * (1 - Self.labelShare) : cell
        }
        // Room to spare means the size setting is not fighting the family — a square
        // widget, or fewer rows than the share assumes. Take what it asked for; the
        // clamp below is for the case it was written for.
        if iconSide(at: share) >= Self.legibilityFloor { return share }

        var high = share    // known too big a margin
        var low = lowest    // the tightest margin there is
        for _ in 0..<20 {
            let mid = (high + low) / 2
            if iconSide(at: mid) >= Self.legibilityFloor { low = mid } else { high = mid }
        }
    /// `low` is feasible whenever the loop moved it, and ``tightestMarginShare``
    /// when it did not. Returning the latter is the honest floor: not even the
    /// tightest legal margin fits this many rows into this widget, and shrinking
    /// further would clip the corner cells against the system's own rounded clip.
        return iconSide(at: low) >= Self.legibilityFloor ? low : lowest
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
        // The floor is now a *share* rather than the fixed 2 pt this comment used
        // to describe — see ``minimumGapShare``, which is where the measurement
        // that moved it and what it costs in icon size are recorded. It decides
        // where the size setting stops having an effect: for a nine-cell Small
        // widget it binds from about 0.79 upward, so the last fifth of the
        // slider's travel changes nothing, and the editor's footnote quotes the
        // computed size rather than the slider's value for exactly that reason.
        // `available` is the whole widget, not a pre-inset part of it: the margin
        // is taken off here so that one number — the size setting — decides both
        // how much of the widget goes to the outer border and how much to the
        // gaps, rather than an inset being applied by every caller and this type
        // only owning what is left.
        let marginShare = Self.legibleMarginShare(
            in: available, columns: columns, rows: rows,
            showsTitles: showsTitles, iconScale: iconScale
        )
        self.margin = available.width * marginShare

        // What is left for the cells and the gaps between them. Never negative:
        // a container smaller than its own margin is a layout bug, but a
        // negative frame turns it into a crash.
        let inner = CGSize(
            width: max(0, available.width - 2 * self.margin),
            height: max(0, available.height - 2 * self.margin)
        )

        // Floored at a *share* rather than at a point count — see
    // ``minimumGapShare`` for the measurement that moved it and for the 4% of
    // icon size it costs above scale 0.79. Below that scale this line changes
    // nothing: the curve's own value is already larger.
    self.spacing = Self.spacing(
        in: inner,
        gapShare: Self.gapShare(forIconScale: iconScale)
    )

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

    /// What the square cell would measure for a candidate grid, or 0 if none fits.
    ///
    /// ## Why this is a question and not a layout
    ///
    /// The direct-launch panel has to choose a shape — how many columns and rows —
    /// for a widget whose size it does not know until the view runs, and the honest
    /// way to choose is to ask what each candidate would cost in cell size and take
    /// the densest one that still clears a floor. That is exactly what the private
    /// arithmetic in ``init(tileCount:columns:in:showsTitles:iconScale:)`` does for
    /// one candidate; this exposes it without the label reservation, which a
    /// candidate has not decided yet.
    ///
    /// Public because the panel lives in the widget target and this is the only
    /// copy of the arithmetic. The alternative — a per-family table in the view —
    /// is the shape that once shipped 11.4 pt icons on a medium widget.
    ///
    /// All three shares are passed in rather than defaulted to the standard ones, so
    /// a caller asking about a non-standard setting asks the same question the
    /// layout would answer.
    public static func cell(
        in available: CGSize,
        columns: Int,
        rows: Int,
        gapShare: CGFloat,
        marginShare: CGFloat
    ) -> CGFloat {
        guard columns > 0, rows > 0 else { return 0 }
        let margin = available.width * marginShare
        let inner = CGSize(
            width: max(0, available.width - 2 * margin),
            height: max(0, available.height - 2 * margin)
        )
        let spacing = Self.spacing(in: inner, gapShare: gapShare)
        let byWidth = (inner.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let byHeight = (inner.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
        return max(0, min(byWidth, byHeight))
    }

    /// The dimension the **gap** is measured against.
    ///
    /// ## Why this is not just the width
    ///
    /// The gap has always been a *share of the widget's width*, and that was right
    /// while the only widget was square: 18 pt of a 170 pt small widget is 18 pt on
    /// both axes, so width stood in for "the room there is". A medium widget is
    /// 349 × 166 and breaks the substitution — the same share is 37 pt top and
    /// bottom, and the height is what actually runs out.
    ///
    /// The smaller dimension is the honest basis for the gap, because that is what
    /// the gaps between cells are competing with the cells for. For a square widget
    /// it *is* the width — so the small widget, whose 37.2 pt icon and 11.2 pt gap
    /// are pinned by ``WidgetGridTests``, is untouched by this.
    ///
    /// ## The margin is a separate case
    ///
    /// The margin is still `available.width * share` — see where ``init`` assigns
    /// it — and deliberately so. Rebasing it too would change the small widget's
    /// pinned 18 pt (that *is* the width share at 0.5), and the medium-widget fix
    /// does not need it: the legibility clamp in ``legibleMarginShare(in:columns:rows:showsTitles:iconScale:)``
    /// is what pulls the margin back in there. So this function governs the gap
    /// only, and a reader should not take the smaller dimension as a property of
    /// both shares.
    ///
    /// An unbounded or unmeasured height means the layout is width-driven — a
    /// preview inside an `aspectRatio`, or a caller with no height yet — and there
    /// the width is all there is to go on.
    static func basis(_ size: CGSize) -> CGFloat {
        guard size.height > 0, size.height.isFinite else { return size.width }
        return min(size.width, size.height)
    }

    /// The gap between cells, on whichever axis is tighter.
    ///
    /// Factored out so ``cell(in:columns:rows:gapShare:marginShare:)`` and
    /// ``init(tileCount:columns:in:showsTitles:iconScale:)`` cannot drift: the
    /// whole point of the probe is that it answers the question the layout will
    /// answer, and a second copy of this arithmetic is exactly how the panel once
    /// chose a shape the grid did not draw.
    static func spacing(in inner: CGSize, gapShare: CGFloat) -> CGFloat {
        let basis = Self.basis(inner)
        return max(basis * Self.minimumGapShare, basis * gapShare)
    }

    /// The widget's own corner radius, in points.
    ///
    /// Measured, not chosen: the system clips a widget's content to a rounded rect
    /// of this radius, and draws its own glass to the same shape. It is needed here
    /// rather than by the grid, because a grid never draws the widget's outline —
    /// only the direct-launch panel does, to mark itself as its own surface
    /// (``DirectLaunchPanelView``).
    ///
    /// The system clips for free, so a full-bleed fill needs no radius of its own.
    /// A *stroke* does: it is drawn inside this circle, and matching the number is
    /// what keeps the line from reading as a cheap outline a few points inside the
    /// system's own glass edge.
    public static let widgetCornerRadius: CGFloat = 27.7

    /// The corner radius of an icon in this grid.
    ///
    /// Here for the same reason as everything else on this type. The widget drew
    /// a fixed 8 pt and the preview drew `side * 0.22`, so a 3×3 grid was making
    /// two different shapes of the same artwork depending on where you looked.
    public var cornerRadius: CGFloat { iconSide * 0.22 }
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
            "3 × 3，直接显示 8 个 App，图标约 37pt。第 9 格是「更多」入口——文件夹里超过 8 个之后，点它展开全部。只影响小尺寸；中号按 5 × 2 排，大号按 4 × 4 排。"
        case .four:
            "2 × 2，直接显示 3 个 App，图标约 60pt——和系统桌面图标一样大。第 4 格是「更多」入口，点它展开文件夹里的全部 App。"
        }
    }

    /// How many icons across, in a widget of the given size.
    ///
    /// The 九宫格/四宫格 choice only reaches the small widget, because it is a
    /// question about a square: how much of the square an icon may take. A wide
    /// widget runs out of *height* first and has a different problem.
    ///
    /// ## Why medium is five columns and not three
    ///
    /// It was three, and the note here used to say the wider families needed no
    /// count of their own "because the icons there are already full size". Measured,
    /// that was false. The cell is the smaller of the width fit and the height fit
    /// (see ``init(tileCount:columns:in:showsTitles:iconScale:)``); a 349 × 166
    /// widget runs out of height, so the cell is height-sized and the columns take
    /// only what they need. Three of them measured **94 pt of a 349 pt width** —
    /// 27%, with about 127 pt of empty plate on each side, and a 28 pt icon rather
    /// than the 60 pt "full size" the old note assumed. The widget read as a small
    /// cluster floating in the middle of a wide box.
    ///
    /// Five columns × two rows measures 227 pt (65%) and gives a **41 pt** icon at
    /// the same setting: wider *and* bigger, because the row count, not the column
    /// count, was what starved the cells.
    ///
    /// ## Why large is four × four
    ///
    /// Large was three × three for the same inherited reason, and the cost there is
    /// capacity rather than proportion: measured at the shipping default, a 3 × 3
    /// fills 65% of the width and 83% of the height with a comfortable 67.8 pt icon
    /// — so it looked fine, and it showed **8** apps. Once medium became 5 × 2 the
    /// larger widget was showing *fewer* apps than the smaller one, which is the
    /// wrong way round for a launcher.
    ///
    /// Four × four fills the same 66% / 83% and shows 15 apps at 48.5 pt — still
    /// three quarters of a Home Screen icon, and comfortably above
    /// ``legibilityFloor``.
    ///
    /// Four × three is the obvious middle and was measured rather than assumed: it
    /// draws the *same* 48.5 pt icon as 4 × 4, because the width binds either way,
    /// while showing four fewer apps and using only 62% of the height. It is worse
    /// than both neighbours, so it is not offered.
    public func columns(for family: WidgetFamily) -> Int {
        switch (self, family) {
        case (.four, .systemSmall):
            return 2
        case (_, .systemSmall):
            return 3
        case (_, .systemMedium):
            return 5
        case (_, .systemLarge):
            return 4
        case (_, .systemExtraLarge), (_, .systemExtraLargePortrait):
            return 4
        default:
            return 3
        }
    }

    /// How many cells this grid draws, which is every cell in the rectangle.
    ///
    /// Not the same as ``capacity(for:)`` once a folder overflows, and the two
    /// being different numbers is the whole of the nesting feature: the grid
    /// draws this many cells, and the last of them is a door rather than a ninth
    /// app.
    public func cellCount(for family: WidgetFamily) -> Int {
        let columns = columns(for: family)
        // Rows per family, so the grid is a rectangle that fills the widget
        // rather than a square that leaves the bottom third bare.
        let rows: Int
        switch family {
        case .systemSmall: rows = columns          // square widget, square grid
        case .systemMedium: rows = 2               // 5 × 2 — see columns(for:)
        case .systemLarge: rows = 4                // 4 × 4 — see columns(for:)
        case .systemExtraLarge, .systemExtraLargePortrait: rows = 3
        default: rows = columns
        }
        return columns * rows
    }

    /// How many apps a folder can show *directly* — what the widget draws as
    /// apps, with the rest reachable behind ``nestedCell``.
    ///
    /// One less than the cell count, always, because the last cell is reserved
    /// for the door. It is reserved even when the folder would not need it, so
    /// that adding a tenth app to a nine-cell folder rearranges nothing: the
    /// first eight stay exactly where they were and the ninth cell changes from
    /// an app to a door. Deciding the reservation from the *current* tile count
    /// instead would make the ninth app jump out of its cell the moment a tenth
    /// arrived, which is the reflow users read as data loss.
    ///
    /// A one-cell grid would have nothing left to lay out, so the subtraction
    /// bottoms out at one rather than at zero.
    public func capacity(for family: WidgetFamily) -> Int {
        max(1, cellCount(for: family) - 1)
    }

    /// The index of the cell that opens the rest, or `nil` when nothing has
    /// overflowed and every cell holds an app.
    ///
    /// Read by both the widget and the editor's preview so the two agree about
    /// where the door is — the same reason everything else on this type is
    /// shared.
    public func nestedCell(for family: WidgetFamily, tileCount: Int) -> Int? {
        tileCount > capacity(for: family) ? capacity(for: family) : nil
    }
}

public extension WidgetFamily {
    /// How many apps this family shows directly at the default grid.
    var gridCapacity: Int { FolderGrid.default.capacity(for: self) }

    /// How many icons this family draws across at the default grid.
    var gridColumns: Int { FolderGrid.default.columns(for: self) }

    /// How many cells this family's grid draws at the default grid.
    var gridCellCount: Int { FolderGrid.default.cellCount(for: self) }
}
