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
        // and the gap to its 2 pt floor, which is what buys the icons 51.4 pt.
        #expect(abs(largest.iconSide - 51.4) < 0.1)
    }

    /// The floor means the setting stops changing anything well before the
    /// slider ends. That is not a bug — it is why the editor quotes the computed
    /// size instead of the slider's own value — but it is the kind of dead zone
    /// that gets "fixed" by someone lowering the floor later, which would draw
    /// the icons edge to edge at the maximum. Pin it down.
    @Test("The gap never closes entirely")
    func gapKeepsAFloor() {
        let container = CGSize(width: 134, height: 134)
        let largest = FolderGridMetrics(
            tileCount: 9, columns: 3, in: container, iconScale: 1
        )
        #expect(largest.spacing == 2)
    }

    /// A folder written before the size existed has no key for it, and must come
    /// back at the size it was already being drawn at rather than at one end of
    /// the range — otherwise merely *opening* the app would resize the user's
    /// Home Screen.
    @Test("A folder from before the size setting keeps its layout")
    func decodesAtTheStandardSize() throws {
        let json = """
        { "id": "\(UUID().uuidString)", "name": "常用", "updatedAt": 0 }
        """
        let folder = try FolderCoding.makeDecoder().decode(Folder.self, from: Data(json.utf8))
        #expect(folder.iconScale == FolderGridMetrics.defaultIconScale)
    }

    /// And a value outside the range is clamped rather than rejected. A decode
    /// failure here is not a warning: `FolderStore` quarantines the whole file.
    @Test("An out-of-range size is clamped, not rejected", arguments: [-3.0, 7.5])
    func clampsOutOfRangeSize(value: Double) throws {
        let json = """
        { "id": "\(UUID().uuidString)", "name": "常用", "iconScale": \(value), "updatedAt": 0 }
        """
        let folder = try FolderCoding.makeDecoder().decode(Folder.self, from: Data(json.utf8))
        #expect(folder.iconScale >= 0 && folder.iconScale <= 1)
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

    /// A folder from before the grid setting existed has no key for it and must
    /// come back as 九宫格 — losing five apps to a setting nobody made would be
    /// the worst kind of silent data loss, because the tiles are still in the
    /// library and only the Home Screen stops showing them.
    @Test("A folder from before the grid setting stays nine")
    func decodesToNineGrid() throws {
        let json = """
        { "id": "\(UUID().uuidString)", "name": "常用", "updatedAt": 0 }
        """
        let folder = try FolderCoding.makeDecoder().decode(Folder.self, from: Data(json.utf8))
        #expect(folder.grid == .nine)
    }

    /// And an unrecognised value falls back rather than throwing, for the same
    /// reason `plate` does: a throw here quarantines the whole library.
    @Test("An unrecognised grid falls back rather than failing")
    func unrecognisedGridFallsBack() throws {
        let json = """
        { "id": "\(UUID().uuidString)", "name": "常用", "grid": "sixteen", "updatedAt": 0 }
        """
        let folder = try FolderCoding.makeDecoder().decode(Folder.self, from: Data(json.utf8))
        #expect(folder.grid == .nine)
    }
}