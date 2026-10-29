import CoreGraphics
import CoreText
import WidgetKit

/// Where the icons in a folder grid go.
///
/// Shared between the widget and the app's preview, because "what the widget
/// will look like" is the only thing the preview is for. Two independent layout
/// calculations would drift, and the drift would be invisible until a user
/// complained that the preview lied to them.
///
/// Icons remain square. Larger families distribute columns across the available
/// width and reserve the name's height independently.
public struct FolderGridMetrics: Sendable, Equatable {
    /// How many icons fit across.
    public let columns: Int
    /// How many rows are needed for the tiles given.
    public let rows: Int
    /// Side length of one square icon, in points.
    public let iconSide: CGFloat
    /// Width of the whole cell, including room for its name. Artwork is centered
    /// within this width and remains `iconSide` square.
    public let cellWidth: CGFloat
    /// Gap between cells, in points.
    public let spacing: CGFloat

    /// The outer margin the grid leaves on every side, in points.
    public let margin: CGFloat
    /// Whether each icon carries its name underneath.
    public let showsTitles: Bool

    /// Vertical space one name takes under its icon, in points; 0 when titles
    /// are off.
    /// Includes the gap between the icon and the name.
    public let labelHeight: CGFloat

    /// Automatic layouts retain the icon-plus-name height. Custom geometry
    /// fixes the whole tap cell so changing icon size cannot move the gaps.
    public var cellHeight: CGFloat { fixedCellHeight ?? iconSide + labelHeight }
    private var fixedCellHeight: CGFloat? = nil

    /// The size the whole grid occupies.
    public var size: CGSize {
        CGSize(
            width: cellWidth * CGFloat(columns) + spacing * CGFloat(max(0, columns - 1)),
            height: cellHeight * CGFloat(rows) + spacing * CGFloat(max(0, rows - 1))
        )
    }

    /// Font size shared by the widget and its preview.
    public let titleFontSize: CGFloat

    /// Gap between an icon and its name.
    public let titleSpacing: CGFloat

    /// What fraction of a cell a name is allowed to take when titles are on.
    private static let labelShare: CGFloat = 0.26

    private static let largerTitleFontSize: CGFloat = 12
    private static let largerTitleSpacing: CGFloat = 2
    private static let largerTitleLineHeight: CGFloat = {
        guard let font = CTFontCreateUIFontForLanguage(.system, largerTitleFontSize, nil) else {
            return ceil(largerTitleFontSize * 1.3)
        }
        return ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
    }()

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

    /// Legacy small-grid gap curve. The point-based larger-family layout uses
    /// per-cell dimensions instead.
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

    /// Target minimum for the legacy small-grid margin adjustment. Containers
    /// too small to fit it still respect their available bounds.
    public static let legibilityFloor: CGFloat = 28

    /// Legacy small-grid margin curve, expressed as a share of its width.
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

    /// Keeps the legacy layout's icons above the target floor when its minimum
    /// margin allows it. Medium and large families use independent constraints.
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
        // If the target cannot fit, respect the minimum margin.
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
    ///   - family: larger families use bounded point margins and independently
    ///     sized names. Omit it to preserve the existing small-grid geometry.
    ///   - density: dense larger grids use smaller gaps and real font metrics;
    ///     the small family's geometry is independent of this setting.
    ///   - spacing: optional cell gap in points. Zero is intentional; values
    ///     that cannot fit are reduced while retaining drawable cell space.
    ///   - margin: optional outer inset in points. With either override set,
    ///     cells stay fixed and iconScale sizes the artwork inside each cell.
    public init(
        tileCount: Int,
        columns: Int,
        in available: CGSize,
        showsTitles: Bool = false,
        iconScale: Double = FolderGridMetrics.defaultIconScale,
        family: WidgetFamily? = nil,
        density: FolderDensity = .standard,
        spacing: Int? = nil,
        margin: Int? = nil
    ) {
        let legacy = Self(legacyTileCount: tileCount, columns: columns, in: available,
                          showsTitles: showsTitles, iconScale: iconScale, family: family, density: density)
        // Keep the original arithmetic and every normal default field exact.
        // Its invalid/nonfinite or overflowing results are not a compatibility
        // contract: these use the same bounded path as explicit geometry.
        if spacing == nil, margin == nil, legacy.fits(available) {
            self = legacy
        } else {
            self.init(customTileCount: tileCount, columns: columns, in: available,
                      showsTitles: showsTitles, iconScale: iconScale, family: family, density: density,
                      requestedSpacing: spacing, requestedMargin: margin)
        }
    }

    private init(
        legacyTileCount tileCount: Int,
        columns: Int,
        in available: CGSize,
        showsTitles: Bool,
        iconScale: Double,
        family: WidgetFamily?,
        density: FolderDensity
    ) {
        let columns = max(1, columns)
        let rows = (max(1, tileCount) - 1) / columns + 1
        self.columns = columns
        self.rows = rows
        self.showsTitles = showsTitles

        let isPortrait: Bool
        if #available(macOS 27.0, *) { isPortrait = family == .systemExtraLargePortrait }
        else { isPortrait = false }
        if family == .systemMedium || family == .systemLarge || isPortrait {
            let width = available.width.isFinite ? max(0, available.width) : 0
            let height = available.height.isFinite ? max(0, available.height) : width
            let scale = CGFloat(iconScale.isFinite ? min(1, max(0, iconScale)) : Self.defaultIconScale)
            let nominalCell = min(width / CGFloat(columns), height / CGFloat(rows))
            let adaptive = density != .standard || isPortrait
            let densityScale = min(1, max(0, (scale - 0.5) * 2))

            // Per-cell spacing prevents a wide, short widget from spending its
            // height on margins derived from the whole widget's width.
            let desiredMargin = adaptive
                ? max(2, min(12, max(4, nominalCell * 0.12)) * (1 - densityScale * 0.5))
                : min(12, max(6, nominalCell * (0.20 - 0.12 * scale)))
            self.margin = min(desiredMargin, min(width, height) / 2)
            let innerWidth = max(0, width - 2 * margin)
            let innerHeight = max(0, height - 2 * margin)
            let desiredSpacing = adaptive
                ? max(1.5, min(10, max(2, nominalCell * 0.09)) * (1 - densityScale * 0.55))
                : min(10, max(4, nominalCell * (0.18 - 0.12 * scale)))
            self.spacing = min(
                desiredSpacing,
                innerWidth / CGFloat(max(1, columns - 1)),
                innerHeight / CGFloat(max(1, rows - 1))
            )
            self.cellWidth = max(0, (innerWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns))
            let rowHeight = max(0, (innerHeight - spacing * CGFloat(rows - 1)) / CGFloat(rows))
            let fontSize = adaptive ? min(density == .dense ? 10 : 12, max(8, nominalCell * 0.22)) : Self.largerTitleFontSize
            let titleSpacing: CGFloat = adaptive && density == .dense ? 1.5 : Self.largerTitleSpacing
            let lineHeight: CGFloat
            if adaptive, let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil) {
                lineHeight = ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
            } else {
                lineHeight = Self.largerTitleLineHeight
            }
            let fullLabelHeight = lineHeight + titleSpacing
            self.labelHeight = showsTitles ? min(fullLabelHeight, rowHeight) : 0
            let labelScale = labelHeight / fullLabelHeight
            self.titleFontSize = fontSize * labelScale
            self.titleSpacing = titleSpacing * labelScale
            self.iconSide = max(0, min(cellWidth, rowHeight - labelHeight))
            return
        }

        // Preserve the established small-widget layout, including its existing
        // label proportions and icon-size settings.
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
        self.cellWidth = iconSide
        self.labelHeight = reserved
        self.titleFontSize = showsTitles ? max(7, reserved * 0.78) : 0
        self.titleSpacing = showsTitles ? max(1, reserved * 0.15) : 0
    }

    private func fits(_ available: CGSize) -> Bool {
        guard available.width.isFinite, available.width >= 0,
              (available.height.isFinite && available.height >= 0) || available.height == .infinity,
              [iconSide, cellWidth, cellHeight, spacing, margin, labelHeight, titleFontSize,
               titleSpacing, size.width, size.height, cornerRadius].allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            return false
        }
        if showsTitles, titleFontSize > cellHeight { return false }
        return size.width + 2 * margin <= available.width + max(1, available.width) * 1e-12
            && (available.height == .infinity
                || size.height + 2 * margin <= available.height + max(1, available.height) * 1e-12)
    }

    /// Explicit values control cell geometry; iconScale only changes artwork
    /// inside those cells. Preserve margin first, then reduce spacing as needed
    /// to retain up to one point per cell on both axes. Zero is intentional.
    private init(customTileCount tileCount: Int, columns: Int, in available: CGSize,
                 showsTitles: Bool, iconScale: Double, family: WidgetFamily?, density: FolderDensity,
                 requestedSpacing: Int?, requestedMargin: Int?) {
        let columns = max(1, columns)
        let rows = (max(1, tileCount) - 1) / columns + 1
        self.columns = columns
        self.rows = rows
        self.showsTitles = showsTitles
        let c = CGFloat(columns), r = CGFloat(rows)
        // This ceiling only affects astronomical inputs and leaves enough
        // arithmetic headroom for a width-driven grid with many rows.
        let limit = CGFloat.greatestFiniteMagnitude / max(4, c, r) / 4
        let width = available.width.isFinite ? min(limit, max(0, available.width)) : 0
        let height: CGFloat? = available.height == .infinity ? nil
            : (available.height.isFinite ? min(limit, max(0, available.height)) : 0)
        let scale = iconScale.isFinite ? min(1, max(0, iconScale)) : Self.defaultIconScale
        let safeSize = CGSize(width: width, height: height ?? .infinity)
        let suggested = Self(legacyTileCount: tileCount, columns: columns, in: safeSize,
                             showsTitles: showsTitles, iconScale: scale, family: family, density: density)
        let floor = min(1, width / c, height.map { $0 / r } ?? width / c)
        let wantedMargin = requestedMargin.map { CGFloat(min(40, max(0, $0))) }
            ?? (suggested.margin.isFinite ? max(0, suggested.margin) : 0)
        let marginCap = min(max(0, (width - c * floor) / 2),
                            height.map { max(0, ($0 - r * floor) / 2) } ?? .greatestFiniteMagnitude)
        let margin = min(wantedMargin, marginCap)
        self.margin = margin
        let innerWidth = max(0, width - 2 * margin)
        let innerHeight = height.map { max(0, $0 - 2 * margin) }
        let wantedSpacing = requestedSpacing.map { CGFloat(min(24, max(0, $0))) }
            ?? (suggested.spacing.isFinite ? max(0, suggested.spacing) : 0)
        let widthCap = columns > 1 ? max(0, (innerWidth - c * floor) / (c - 1)) : .greatestFiniteMagnitude
        let heightCap = rows > 1 ? innerHeight.map { max(0, ($0 - r * floor) / (r - 1)) }
            ?? .greatestFiniteMagnitude : .greatestFiniteMagnitude
        let spacing = min(wantedSpacing, widthCap, heightCap)
        self.spacing = spacing
        let cellWidth = max(0, (innerWidth - spacing * (c - 1)) / c)
        let rowHeight = innerHeight.map { max(0, ($0 - spacing * (r - 1)) / r) } ?? cellWidth
        self.cellWidth = cellWidth
        self.fixedCellHeight = rowHeight

        // Text size must not change with iconScale in a fixed cell: otherwise
        // a larger icon setting could give its extra room away to a larger name.
        let textReference = Self(legacyTileCount: tileCount, columns: columns, in: safeSize,
                                 showsTitles: showsTitles, iconScale: Self.defaultIconScale,
                                 family: family, density: density)
        let text = Self.fittedTitle(showsTitles: showsTitles, budget: max(0, rowHeight - floor),
                                    preferredFont: textReference.titleFontSize,
                                    preferredSpacing: textReference.titleSpacing)
        self.labelHeight = text.height
        self.titleFontSize = text.font
        self.titleSpacing = text.spacing
        let iconBudget = max(0, min(cellWidth, rowHeight - text.height))
        self.iconSide = min(iconBudget, max(floor, iconBudget * CGFloat(0.5 + 0.5 * scale)))
    }

    private static func fittedTitle(showsTitles: Bool, budget: CGFloat,
                                    preferredFont: CGFloat, preferredSpacing: CGFloat)
        -> (height: CGFloat, font: CGFloat, spacing: CGFloat) {
        guard showsTitles, budget >= 1 else { return (0, 0, 0) }
        // Pathological dimensions must not ask Core Text to create a font with
        // an astronomical point size; real widget recommendations stay below 64.
        let font = min(64, preferredFont.isFinite && preferredFont > 0 ? preferredFont : largerTitleFontSize)
        let gap = preferredSpacing.isFinite && preferredSpacing > 0 ? preferredSpacing : largerTitleSpacing
        func lineHeight(_ size: CGFloat) -> CGFloat {
            guard let value = CTFontCreateUIFontForLanguage(.system, size, nil) else { return ceil(size * 1.3) }
            return ceil(CTFontGetAscent(value) + CTFontGetDescent(value) + CTFontGetLeading(value))
        }
        var scale = min(1, budget / (lineHeight(font) + gap))
        for _ in 0..<8 {
            let scaledFont = font * scale
            let scaledGap = gap * scale
            guard scaledFont > 0 else { break }
            let height = lineHeight(scaledFont) + scaledGap
            if height <= budget { return (height, scaledFont, scaledGap) }
            scale *= (budget / height).nextDown
        }
        return (0, 0, 0)
    }

    /// Probes a square cell in the legacy share-based layout, before reserving
    /// label space. The medium/large initializer does not use this probe.
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

    /// Basis of the legacy proportional gap. An unbounded height makes it
    /// width-driven; otherwise the shorter axis limits the gap.
    static func basis(_ size: CGSize) -> CGFloat {
        guard size.height > 0, size.height.isFinite else { return size.width }
        return min(size.width, size.height)
    }

    /// Shared by the legacy initializer and its square-cell probe.
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

    /// Larger-family density does not change the small four/nine-cell choice.
    public func columns(for family: WidgetFamily, density: FolderDensity = .standard) -> Int {
        switch (self, family) {
        case (.four, .systemSmall):
            return 2
        case (_, .systemSmall):
            return 3
        case (_, .systemMedium):
            switch density { case .standard: return 5; case .spacious: return 4; case .dense: return 7 }
        case (_, .systemLarge):
            switch density { case .standard: return 4; case .spacious: return 3; case .dense: return 7 }
        case (_, .systemExtraLargePortrait):
            switch density { case .standard: return 5; case .spacious: return 4; case .dense: return 7 }
        case (_, .systemExtraLarge):
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
    public func cellCount(for family: WidgetFamily, density: FolderDensity = .standard) -> Int {
        let columns = columns(for: family, density: density)
        // Rows per family, so the grid is a rectangle that fills the widget
        // rather than a square that leaves the bottom third bare.
        let rows: Int
        switch family {
        case .systemSmall: rows = columns          // square widget, square grid
        case .systemMedium: rows = density == .dense ? 3 : 2
        case .systemLarge:
            switch density { case .standard: rows = 4; case .spacious: rows = 3; case .dense: rows = 7 }
        case .systemExtraLargePortrait:
            switch density { case .standard: rows = 8; case .spacious: rows = 6; case .dense: rows = 11 }
        case .systemExtraLarge: rows = 3
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
    public func capacity(for family: WidgetFamily, density: FolderDensity = .standard) -> Int {
        max(1, cellCount(for: family, density: density) - 1)
    }

    /// The index of the cell that opens the rest, or `nil` when nothing has
    /// overflowed and every cell holds an app.
    ///
    /// Read by both the widget and the editor's preview so the two agree about
    /// where the door is — the same reason everything else on this type is
    /// shared.
    public func nestedCell(for family: WidgetFamily, tileCount: Int, density: FolderDensity = .standard) -> Int? {
        let capacity = capacity(for: family, density: density)
        return tileCount > capacity ? capacity : nil
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
