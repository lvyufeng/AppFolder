import Testing
import WidgetKit

@testable import AppFolderKit

/// The widget's grid is one table read by two sides: the timeline provider uses
/// ``WidgetFamily/gridCapacity`` to truncate the folder, the widget view uses
/// ``WidgetFamily/gridColumns`` to lay the result out. Nothing forces them to
/// agree at the type level, and they did not — Small truncated to four tiles
/// while drawing two columns, so a folder of nine apps silently lost five.
///
/// These tests are cheap and they are the whole reason the table moved here: the
/// failure they catch is invisible in a build and shows up only as a user
/// noticing that an app they put in a folder is not on the Home Screen.
@Suite("Widget grid")
struct WidgetGridTests {
    /// Every family is laid out as a full grid — `gridCellCount` cells across in
    /// `gridColumns` columns — so the two numbers have to be consistent with each
    /// other, and a widget must never reserve a cell it has nothing to draw in.
    /// `.systemExtraLargePortrait` is left out: it is iOS-only, and these tests
    /// run on the macOS host.
    @Test("The cell count is a whole number of rows of columns", arguments: [
        WidgetFamily.systemSmall,
        .systemMedium,
        .systemLarge,
        .systemExtraLarge,
    ])
    func cellCountIsWholeRows(family: WidgetFamily) {
        #expect(family.gridCellCount % family.gridColumns == 0)
        #expect(family.gridCellCount > 0)
        #expect(family.gridColumns > 0)
    }

    /// The product requirement this table exists to satisfy: nine cells in the
    /// 2 × 2 widget, three across.
    ///
    /// Eight *apps*, not nine — the ninth cell is the door. That subtraction is
    /// the nesting feature, and it is asserted separately below because it is the
    /// kind of one-off that a later change to `capacity` could quietly undo.
    @Test("A small widget draws nine cells, three across")
    func smallDrawsNineCells() {
        #expect(WidgetFamily.systemSmall.gridCellCount == 9)
        #expect(WidgetFamily.systemSmall.gridColumns == 3)
        #expect(WidgetFamily.systemSmall.gridCapacity == 8)
    }

    /// The grid is handed the whole widget and takes its own margin off, so
///     `size` alone is not the footprint — the margin has to be counted too. A
///     grid that overflows its widget would silently drop its bottom row.
    @Test("The grid fits its widget at every size setting", arguments: Array(stride(from: 0.0, through: 1.0, by: 0.05)))
    func gridNeverOverflows(scale: Double) {
        let container = CGSize(width: 170, height: 170)
        let metrics = FolderGridMetrics(
            tileCount: WidgetFamily.systemSmall.gridCellCount,
            columns: WidgetFamily.systemSmall.gridColumns,
            in: container,
            showsTitles: false,
            iconScale: scale
        )
        #expect(metrics.size.width + 2 * metrics.margin <= container.width + 0.01)
        #expect(metrics.size.height + 2 * metrics.margin <= container.height + 0.01)
        #expect(metrics.iconSide > 0)
    }

    /// Labels fit in Small now that the grid sizes its own margin.
    ///
    /// This reverses an earlier rule that Small never drew names. That rule was
    /// arithmetic done against a grid the system had already inset by 18 pt on
    /// each side: nine cells started from 134 pt of usable width and a labelled
    /// icon came out at 27.5 pt, too small to recognise. With the margin under
    /// the size setting's control the same nine cells are laid out from 134 pt of
    /// *cell* width instead, and a labelled icon is about 27.5 pt — still small,
    /// but the unlabelled icon beside it is 37.2 pt, and the user choosing names
    /// knows what they are trading.
    @Test("A small widget can carry names")
    func smallWidgetFitsNames() {
        let container = CGSize(width: 170, height: 170)
        let labelled = FolderGridMetrics(
            tileCount: 9, columns: 3, in: container, showsTitles: true
        )
        let plain = FolderGridMetrics(
            tileCount: 9, columns: 3, in: container, showsTitles: false
        )
        #expect(labelled.labelHeight > 0)
        #expect(labelled.iconSide < plain.iconSide)
        #expect(labelled.iconSide > 25)
    }

    /// The outer margin is the second half of the size control, and the half
    /// that answers "the icons sit too far from the edge". It has to run from the
    /// system's own 18 pt down to close to the widget's border — an earlier
    /// attempt at this only moved the *gap*, which left the 18 pt margin in place
    /// and so left the complaint unaddressed.
    @Test("A larger setting moves the icons towards the widget's edge")
    func largerScaleTightensTheMargin() {
        let container = CGSize(width: 170, height: 170)
        let standard = FolderGridMetrics(
            tileCount: 9, columns: 3, in: container,
            iconScale: FolderGridMetrics.defaultIconScale
        )
        let largest = FolderGridMetrics(
            tileCount: 9, columns: 3, in: container, iconScale: 1
        )
        // The system's margin, which is where every library written before this
        // setting existed is drawn.
        #expect(abs(standard.margin - 18) < 0.1)
        // Close to the edge, but clear of the widget's ~27.7 pt corner radius:
        // a corner icon's own corner survives the clip while the margin stays
        // above about 4.8 pt for this cell size. 6 pt leaves the margin visible.
        #expect(largest.margin >= 5 && largest.margin <= 8)
    }

    /// Turning the control up has to make the icons bigger, or the setting is
    /// decoration.
    @Test("A larger setting draws larger icons")
    func largerScaleDrawsLargerIcons() {
        let container = CGSize(width: 170, height: 170)
        let smallest = FolderGridMetrics(
            tileCount: 9, columns: 3, in: container, iconScale: 0
        )
        let standard = FolderGridMetrics(
            tileCount: 9, columns: 3, in: container,
            iconScale: FolderGridMetrics.defaultIconScale
        )
        let largest = FolderGridMetrics(
            tileCount: 9, columns: 3, in: container, iconScale: 1
        )

        #expect(smallest.iconSide < standard.iconSide)
        #expect(standard.iconSide < largest.iconSide)
        // The default has to be the arrangement already on screen, or shipping
        // the control would have resized every folder on the Home Screen the
        // first time it ran: the system's 18 pt margin, the standard gap of
        // width/12, and a 37.2 pt icon are what the pre-slider layout drew.
        #expect(abs(standard.iconSide - 37.2) < 0.1)
        #expect(abs(standard.spacing - 11.2) < 0.1)
        // The top of the range spends both levers: the margin comes in to 6 pt
        // and the gap to its floor, which is what buys the icons 48.3 pt.
        //
        // Was 51.4. The gap's floor moved from a fixed 2 pt to half the standard
        // gap — see ``FolderGridMetrics/minimumGapShare`` — because 2 pt against a
        // 51 pt icon is a 3.9% ratio, which reads as one solid block rather than as
        // a grid, and that is what the 大 setting was reported as drawing. The 3 pt
        // of icon size is what a visible gap costs; the relationship this test is
        // really about (larger setting ⇒ larger icons) still holds, and the
        // assertions above it still pin it.
        #expect(abs(largest.iconSide - 48.3) < 0.1)
    }

    /// The gap never closes entirely, at any size.
    ///
    /// The floor used to be a fixed 2 pt, and this test asserted exactly that
    /// number. It is now half the standard gap as a share of the grid's width,
    /// because a point count cannot express "still visibly separated" when the
    /// thing it must be visible against — the cell — scales with the widget. See
    /// ``FolderGridMetrics/minimumGapShare`` for the measurement that moved it.
    ///
    /// What survives unchanged is the property this test was written for: at the
    /// top of the range the gap is non-zero, so the icons are never drawn edge to
    /// edge. What is newly asserted is that it is non-zero *in proportion* — a
    /// floor met by a hairline would satisfy the old form of this test and still
    /// look exactly like the bug it was meant to prevent.
    @Test("The gap never closes entirely")
    func gapKeepsAFloor() {
        let container = CGSize(width: 134, height: 134)
        let largest = FolderGridMetrics(
            tileCount: 9, columns: 3, in: container, iconScale: 1
        )
        #expect(largest.spacing > 2)

        // The floor binds at the top of the range, so the gap is exactly the floor
        // as a share of the *inner* width — not of the container. The margin is
        // `container * 0.035` at this scale, which is 4.7 pt, not the 6 pt the
        // standard setting leaves.
        let inner = container.width - 2 * largest.margin
        #expect(abs(largest.spacing - inner * FolderGridMetrics.minimumGapShare) < 0.01)

        // And it stays that share of whatever grid it sits in, so the ratio a user
        // actually sees does not drift with the widget's size.
        for width in [134.0, 170.0, 200.0, 300.0, 500.0] as [CGFloat] {
            let m = FolderGridMetrics(
                tileCount: 9, columns: 3, in: CGSize(width: width, height: width), iconScale: 1
            )
            let inner = width - 2 * m.margin
            #expect(abs(m.spacing - inner * FolderGridMetrics.minimumGapShare) < 0.01)
            #expect(m.spacing > 0)
        }
    }

    /// 大 keeps 中's gap-to-icon ratio: the size setting past 中 moves the margin
    /// and nothing else.
    ///
    /// This is the shape of the fix, stated as a property rather than as two
    /// numbers. The complaint was that 大 had "几乎没有间隔" — not that its icons
    /// were too big. The floor is set exactly where the curve reaches it, which is
    /// 中, so the gap stops narrowing there and the remaining travel of the setting
    /// goes entirely into the icons. A future change that widens the gap further
    /// would make 大 and 中 look alike; one that narrows it again would bring back
    /// the original report.
    @Test("Above 中 the gap holds while the icons grow")
    func largeKeepsTheStandardRatios() {
        let container = CGSize(width: 170, height: 170)
        func ratio(_ scale: Double, columns: Int = 3) -> CGFloat {
            let m = FolderGridMetrics(
                tileCount: columns * columns, columns: columns, in: container, iconScale: scale
            )
            return m.spacing / m.iconSide
        }

        for columns in [2, 3] {
            let atMedium = ratio(0.75, columns: columns)
            let atLarge = ratio(1.0, columns: columns)
            #expect(
                abs(atLarge - atMedium) < 0.001,
                "\(columns)×\(columns): 大 draws \(atLarge), 中 draws \(atMedium)"
            )

            // And the icons really are bigger, or the setting is decoration.
            let medium = FolderGridMetrics(
                tileCount: columns * columns, columns: columns, in: container, iconScale: 0.75
            )
            let large = FolderGridMetrics(
                tileCount: columns * columns, columns: columns, in: container, iconScale: 1
            )
            #expect(large.iconSide > medium.iconSide)
        }
    }

    /// The floor leaves everything at or below 中 untouched.
    ///
    /// The reason it is set at 2.95% and not higher: the curve does not reach it
    /// until scale ≈ 0.79, so the arrangement the pre-slider layout drew — and
    /// which the test above pins at a 37.2 pt icon and an 11.2 pt gap — is still
    /// drawn exactly as it was. Raising this floor would silently resize every
    /// existing folder, which is the failure the default's own doc comment warns
    /// about.
    @Test("The floor does not reach the standard size")
    func gapFloorLeavesTheStandardSizeAlone() {
        // The two constants are spelled as separate literals so neither can read
        // the other as a zero-initialized global — see `minimumGapShare`. That
        // makes their relationship the test's job rather than the compiler's.
        #expect(FolderGridMetrics.minimumGapShare == FolderGridMetrics.standardGapShare / 2)

        let container = CGSize(width: 170, height: 170)

        // At and below 中 the curve's own value is at or above the floor, so the
        // floor never *raises* the gap and the arrangement is drawn exactly as
        // before. Equality at 0.75 is the definition, not a coincidence: the floor
        // is `gapShare(0.75)`, chosen there so that the setting's remaining travel
        // goes into the icons rather than into closing the gap.
        for scale in [0.0, 0.25, 0.5, 0.75] {
            let m = FolderGridMetrics(tileCount: 9, columns: 3, in: container, iconScale: scale)
            let inner = container.width - 2 * m.margin
            #expect(
                m.spacing >= inner * FolderGridMetrics.minimumGapShare,
                "the floor must not raise the gap at scale \(scale)"
            )
        }

        let standard = FolderGridMetrics(
            tileCount: 9, columns: 3, in: container,
            iconScale: FolderGridMetrics.defaultIconScale
        )
        #expect(abs(standard.spacing - 11.2) < 0.1, "中 must still draw the original gap")
    }

    // MARK: - Grid shape

    /// The requirement: the small widget draws 3 × 3 or 2 × 2, and each holds one
    /// fewer app than it has cells because the last cell is the door.
    @Test("Four-grid holds three, nine-grid holds eight")
    func gridShapesHoldTheRightCount() {
        #expect(FolderGrid.nine.columns(for: .systemSmall) == 3)
        #expect(FolderGrid.nine.cellCount(for: .systemSmall) == 9)
        #expect(FolderGrid.nine.capacity(for: .systemSmall) == 8)
        #expect(FolderGrid.four.columns(for: .systemSmall) == 2)
        #expect(FolderGrid.four.cellCount(for: .systemSmall) == 4)
        #expect(FolderGrid.four.capacity(for: .systemSmall) == 3)
    }

    // MARK: - Nesting

    /// Over the capacity, the last cell becomes the door — and it is the *last*
    /// cell, not the cell after the last app drawn. Those are the same index, and
    /// the test says which one the code means: the door is pinned to the end of
    /// the grid so that the apps keep their positions.
    @Test("The door is the last cell", arguments: [(FolderGrid.nine, 9), (.four, 4)])
    func doorIsTheLastCell(grid: FolderGrid, cells: Int) {
        #expect(grid.cellCount(for: .systemSmall) == cells)
        #expect(grid.nestedCell(for: .systemSmall, tileCount: cells + 1) == cells - 1)
    }

    /// A folder that fits does not get a door. The empty cells it leaves are
    /// cells, not a door onto nothing: an entry that opened a list of the zero
    /// apps already on screen would be a control that does nothing.
    @Test("A folder that fits has no door", arguments: [0, 1, 2, 8])
    func folderThatFitsHasNoDoor(tileCount: Int) {
        #expect(FolderGrid.nine.nestedCell(for: .systemSmall, tileCount: tileCount) == nil)
    }

    /// The one that is easiest to get wrong, and the reason the reservation is
    /// unconditional: a folder at exactly the capacity has no door, and adding
    /// one more app must not move anything that was already on screen.
    ///
    /// Under a conditional reservation — "reserve a cell only once there is
    /// something to put behind it" — the ninth app of a nine-cell grid sits in
    /// cell 8, and the tenth pushes the door in at cell 8 and demotes the ninth
    /// app... to somewhere. The user sees an app leave the Home Screen at the
    /// moment they add another one, which reads as the new app replacing it.
    @Test("Adding an app past capacity only changes the last cell")
    func growingPastCapacityDisturbsNothing() {
        let grid = FolderGrid.nine
        let capacity = grid.capacity(for: .systemSmall)

        // At capacity: no door, and every cell is an app.
        #expect(grid.nestedCell(for: .systemSmall, tileCount: capacity) == nil)
        for index in 0..<capacity {
            #expect(index != grid.nestedCell(for: .systemSmall, tileCount: capacity + 1))
        }
        // One past: the door takes the last cell, and nothing before it moved.
        #expect(grid.nestedCell(for: .systemSmall, tileCount: capacity + 1) == capacity)
    }

    /// A grid of one cell would have no room for both an app and a door, and
    /// `capacity` subtracting unconditionally would return zero — a folder that
    /// can show nothing at all. No family is that small today; the bound is here
    /// so that one being added later cannot turn into a division by zero.
    @Test("The capacity subtraction bottoming out", arguments: FolderGrid.allCases)
    func capacityNeverReachesZero(grid: FolderGrid) {
        for family: WidgetFamily in [.systemSmall, .systemMedium, .systemLarge] {
            #expect(grid.capacity(for: family) >= 1)
            #expect(grid.capacity(for: family) < grid.cellCount(for: family))
        }
    }

    /// The setting stops at the small size, which is the decision that makes it
    /// worth having: four icons in a medium widget would waste most of the width
    /// to buy an icon size that is already achievable there.
    @Test("The choice does not reach the wider widgets", arguments: [
        WidgetFamily.systemMedium, .systemLarge, .systemExtraLarge,
    ])
    func widerWidgetsIgnoreTheChoice(family: WidgetFamily) {
        #expect(FolderGrid.four.columns(for: family) == FolderGrid.nine.columns(for: family))
    }

    /// Every family, every grid: the cell count is a whole number of rows, so no
    /// cell is ever reserved with nothing to draw in it. `cellCount` and
    /// `columns` are two separate switches over the same family, and nothing in
    /// the type system stops them drifting apart — which is the failure
    /// ``FolderGrid`` exists to fix, one layer up.
    @Test("The cell count is always a whole number of rows", arguments: FolderGrid.allCases)
    func everyGridFillsWholeRows(grid: FolderGrid) {
        for family: WidgetFamily in [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge] {
            #expect(grid.cellCount(for: family) % grid.columns(for: family) == 0)
        }
    }

    /// Four icons at the top of the size range should be about a real Home
    /// Screen icon — that is the whole reason to give up five apps for them. If
    /// this ever stops holding, 四宫格 has no reason to exist.
    @Test("Four-grid icons reach Home Screen size")
    func fourGridIconsAreFullSize() {
        let metrics = FolderGridMetrics(
            tileCount: FolderGrid.four.capacity(for: .systemSmall),
            columns: FolderGrid.four.columns(for: .systemSmall),
            in: CGSize(width: 170, height: 170),
            iconScale: 1
        )
        #expect(metrics.iconSide >= 60)
    }

    /// Nine remains the default the widget's configuration falls back on.
    ///
    /// This used to be tested through `FolderCoding`, decoding a folder written
    /// before the grid setting existed. The folder model is gone; what survives is
    /// the requirement — a widget whose stored grid is absent or unrecognised must
    /// draw 九宫格, because that is where the user's existing picks still fit. The
    /// widget's own `LaunchGrid` (an `AppEnum`) is what enforces it now, and it
    /// does so by declaring `.nine` as its default.
    @Test("Nine is the grid other code falls back to")
    func nineIsTheFallbackGrid() {
        #expect(FolderGrid.default == .nine)
        #expect(FolderGrid.nine.capacity(for: .systemSmall) == 8)
    }
}