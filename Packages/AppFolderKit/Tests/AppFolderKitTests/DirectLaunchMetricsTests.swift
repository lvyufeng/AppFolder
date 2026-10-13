import Testing
import WidgetKit
@testable import AppFolderKit

/// The grid geometry a direct-launch widget draws, which is not a folder's.
///
/// ## Why this suite exists
///
/// The direct-launch widget first shipped using ``FolderGridMetrics/defaultIconScale``,
/// which is 0.5 and is right for a folder. On a *medium* widget that setting spends
/// 37 pt of margin top and bottom — the margin is a share of the widget's width, and
/// a medium widget is only 166 pt tall — leaving 92 pt for three rows. Measured, a
/// nine-slot grid came out with **11.4 pt icons**: unreadable, and too small to hit.
///
/// ## What the first fix missed
///
/// The regression was pinned at 大 (1.0) and only at 大, because that is the setting
/// the medium family was re-admitted at — and the pinned value then hid the bug
/// rather than describing it. 大 is the *best* case: the size setting is the only
/// thing that pulls the margin back in, so the smaller the setting the larger the
/// margin and the smaller the icons, which is backwards from what someone asking for
/// smaller icons wants. Measured at 中 — the shipping default, ``LaunchIconSize/medium``
/// — a nine-slot medium grid was **22.7 pt**; at 小 it was **11.4 pt**, the original
/// number, unfixed. A green suite that said nothing about the arrangement most users
/// run.
///
/// ``FolderGridMetrics`` now clamps the margin so the icon can never fall below
/// ``FolderGridMetrics/legibilityFloor``, and measures the gap and the margin against
/// the widget's *shorter* dimension rather than always its width — for a square widget
/// the two are the same number, which is why the small widget's pinned 37.2 pt icon
/// does not move. This suite asserts the resulting invariant across every setting the
/// picker offers, so the next change to either has to keep it.
///
/// ## Legible was not the same as proportioned
///
/// Clearing the floor left the medium grid *readable* and still wrong: three columns
/// of a height-sized cell measured 94 pt of a 349 pt width — 27%, with about 127 pt
/// of empty plate on each side. The icons were legible but the widget read as a small
/// cluster floating in a wide box, and no assertion here noticed because every one of
/// them was about the icon, not about the space it sat in. Medium is now 5 × 2
/// (``FolderGrid/columns(for:)``), and ``everyGridFillsMostOfItsWidth`` is the case
/// that would have caught it.
///
/// Large had the milder version of the same inheritance and lost on capacity
/// instead: at 3 × 3 it filled the widget acceptably and held **8** apps, so once
/// medium was 5 × 2 the larger widget held fewer than the smaller one. It is 4 × 4
/// now — 15 apps at a 48.5 pt icon — and ``theWideShapesComeFromTheGridRule`` pins
/// that ordering, which is the assertion nobody thought to write.
@Suite("Direct launch metrics")
struct DirectLaunchMetricsTests {
    /// The sizes the system gives the three offered families, in points.
    private static let medium = CGSize(width: 349, height: 166)
    private static let small = CGSize(width: 170, height: 170)
    private static let large = CGSize(width: 349, height: 360)

    /// The scale the widget's own tests run at — 大, 1.0.
    ///
    /// Spelled here rather than imported because the widget target cannot be seen
    /// from the package, so this is a *duplicate* on purpose.
    ///
    /// **This is no longer the scale to check against.** It is kept so the cases
    /// below go on pinning the arrangement they always pinned; the settings that
    /// actually ship are covered by ``everyIconSizeStaysLegible``, which walks all
    /// three. Running only at 大 is what let 中 — the default — regress unnoticed.
    private static let scale: Double = 1.0

    /// One arrangement as the widget actually builds it: how many cells, how many
    /// columns (``FolderGrid/columns(for:)``), and the widget it is drawn in.
    ///
    /// The column counts are part of the arrangement rather than a constant because
    /// they are not the same across families — medium is 5 × 2 and the others are
    /// not — and a test that assumed three everywhere would go on passing while the
    /// widget drew something else.
    private static let arrangements: [(name: String, slots: Int, columns: Int, size: CGSize)] = [
        ("small 3×3", 9, 3, small),
        ("small 2×2", 4, 2, small),
        ("medium 5×2", 10, 5, medium),
        ("large 4×4", 16, 4, large),
    ]

    private func metrics(_ slots: Int, columns: Int, in size: CGSize, scale: Double = Self.scale) -> FolderGridMetrics {
        FolderGridMetrics(
            tileCount: slots, columns: columns, in: size,
            showsTitles: true, iconScale: scale
        )
    }

    /// The width the grid's cells and gaps occupy, without the outer margin — the
    /// number that says how much of a wide widget is used.
    private func contentWidth(_ m: FolderGridMetrics) -> CGFloat {
        CGFloat(m.columns) * m.iconSide + CGFloat(m.columns - 1) * m.spacing
    }

    /// A full medium grid — the arrangement that used to be 11 pt.
    @Test func mediumGridIsTwoRowsOfFive() {
        let m = metrics(10, columns: 5, in: Self.medium)
        #expect(m.columns == 5)
        #expect(m.rows == 2)
        // A Home Screen icon is about 60 pt; the requirement here is legibility and a
        // hit target, so anything at or above the small widget's icon is acceptable
        // and anything near the old 11.4 pt is not.
        #expect(m.iconSide >= 28, "medium icons came out \(m.iconSide) pt")
    }

    /// The shapes the widget draws are the ones ``FolderGrid`` says, and the capacity
/// the widget reads comes from the same place, so the two cannot drift.
    ///
    /// The counts are the numbers the tutorial quotes — 小号 8 个、中号 9 个、大号 15 个
    /// — so a change here has a sentence in `TutorialView` to keep in step. Those
    /// numbers are claims about this table and nothing else.
    @Test func theWideShapesComeFromTheGridRule() {
        #expect(FolderGrid.nine.columns(for: .systemMedium) == 5)
        #expect(FolderGrid.nine.cellCount(for: .systemMedium) == 10)
        #expect(FolderGrid.nine.capacity(for: .systemMedium) == 9)

        #expect(FolderGrid.nine.columns(for: .systemLarge) == 4)
        #expect(FolderGrid.nine.cellCount(for: .systemLarge) == 16)
        #expect(FolderGrid.nine.capacity(for: .systemLarge) == 15)

        // The 九宫格/四宫格 choice is about a square, so it must not move the wide
        // families — both of them are the same shape whichever is picked.
        #expect(FolderGrid.four.columns(for: .systemMedium) == 5)
        #expect(FolderGrid.four.columns(for: .systemLarge) == 4)

        // A launcher's larger widget should not hold fewer apps than its smaller
        // one. Large held 8 against medium's 9 until large changed, which is what
        // this line would have caught.
        #expect(
            FolderGrid.nine.capacity(for: .systemLarge)
                > FolderGrid.nine.capacity(for: .systemMedium)
        )
    }

    /// No family may spend so much on margin that the cells are squeezed.
    ///
    /// The block still fits inside the widget, which is what makes the icons
    /// *look* deliberate rather than merely large.
    @Test func gridFitsItsWidget() {
        for arrangement in Self.arrangements {
            let m = metrics(arrangement.slots, columns: arrangement.columns, in: arrangement.size)
            let width = m.margin * 2 + CGFloat(m.columns) * m.iconSide
                + CGFloat(m.columns - 1) * m.spacing
            let height = m.margin * 2 + CGFloat(m.rows) * m.cellHeight
                + CGFloat(m.rows - 1) * m.spacing
            #expect(width <= arrangement.size.width + 0.5,
                    "\(arrangement.name) is \(width) wide in \(arrangement.size.width)")
            #expect(height <= arrangement.size.height + 0.5,
                    "\(arrangement.name) is \(height) tall in \(arrangement.size.height)")
        }
    }

    /// Every grid uses most of the width it is given.
    ///
    /// ## The failure this pins
    ///
    /// The icon-size assertions above are all about the *icon*, so a grid could clear
    /// every one of them while occupying a quarter of its widget — which is exactly
    /// what the medium family did: 3 columns of a height-sized cell came to 94 pt of
    /// 349, leaving about 127 pt of empty plate on each side. Nothing was illegible
    /// and the widget still looked broken.
    ///
    /// It walks the three size settings for the same reason ``everyIconSizeStaysLegible``
    /// does, and for the same mistake: the share is not constant across them, because
    /// the margin is a share of the width and the setting moves it. Measured with the
    /// shipping shapes the worst case is medium at 小 — 54%, the setting that asks for
    /// the largest margin — and the best is 72%, large at 大. A floor of 0.5 catches
    /// the collapse to 27% this pins without freezing a number ordinary tuning may move.
    @Test func everyGridFillsMostOfItsWidth() {
        let stops: [(name: String, scale: Double)] = [("小", 0.5), ("中", 0.75), ("大", 1.0)]
        for stop in stops {
            for arrangement in Self.arrangements {
                let m = metrics(arrangement.slots, columns: arrangement.columns,
                                in: arrangement.size, scale: stop.scale)
                let share = contentWidth(m) / arrangement.size.width
                #expect(
                    share >= 0.5,
                    "\(arrangement.name) at \(stop.name) uses only \(Int(share * 100))% of its width"
                )
            }
        }
    }

    /// The margin is a share of width, which is exactly why a short widget suffers
    /// from it. This is the property behind the bug, stated so a future change that
    /// derives the margin from height instead can be seen to fix it.
    @Test func theDefaultFolderScaleIsTooGenerousForAMediumWidget() {
        let folder = FolderGridMetrics(
            tileCount: 10, columns: 5, in: Self.medium,
            showsTitles: true, iconScale: FolderGridMetrics.defaultIconScale
        )
        let direct = metrics(10, columns: 5, in: Self.medium)
        #expect(folder.iconSide < direct.iconSide)
        #expect(folder.margin > direct.margin)
    }

    /// Every icon size the picker offers, in every family, is still legible.
    ///
    /// ## Why this is not folded into the case above
    ///
    /// The tests above all run at ``scale`` — 大, 1.0 — because that is the setting
    /// the medium family was re-admitted at. But the picker's **default is 中**
    /// (`LaunchIconSize.medium`, 0.75), and 中 moves the margin *outward*: the margin
    /// is a share of width, so a smaller icon scale spends more of a short widget's
    /// height on margin. That is the exact mechanism behind the 11.4 pt regression,
    /// and pinning only 1.0 would leave it untested — a green suite that says nothing
    /// about the arrangement most users run.
    ///
    /// So this walks all three stops in every family. 小 (0.5) is the worst case —
    /// the gap floor is not yet in play there, so the whole shortfall lands on the
    /// cells — but 中 is walked too, because it is the default and because a clamp
    /// tuned so tightly that the default only just clears the bar is one edit away
    /// from regressing it.
    @Test func everyIconSizeStaysLegible() {
        // `LaunchIconSize.scale`'s three stops, duplicated here for the same reason
        // ``scale`` is: the widget target is not visible from the package.
        let stops: [(name: String, scale: Double)] = [("小", 0.5), ("中", 0.75), ("大", 1.0)]
        for stop in stops {
            for arrangement in Self.arrangements {
                let m = metrics(arrangement.slots, columns: arrangement.columns,
                                in: arrangement.size, scale: stop.scale)
                #expect(
                    m.iconSide >= 28,
                    "\(arrangement.name) at \(stop.name) (\(stop.scale)) came out \(m.iconSide) pt"
                )
            }
        }
    }
}