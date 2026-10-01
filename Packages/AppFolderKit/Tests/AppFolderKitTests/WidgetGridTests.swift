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
    /// Every family is laid out as a full grid — `gridCapacity` cells across in
    /// `gridColumns` columns — so the two numbers have to be consistent with each
    /// other, and a widget must never reserve a cell it has nothing to draw in.
    /// `.systemExtraLargePortrait` is left out: it is iOS-only, and these tests
    /// run on the macOS host.
    @Test("Capacity is a whole number of rows of columns", arguments: [
        WidgetFamily.systemSmall,
        .systemMedium,
        .systemLarge,
        .systemExtraLarge,
    ])
    func capacityIsWholeRows(family: WidgetFamily) {
        #expect(family.gridCapacity % family.gridColumns == 0)
        #expect(family.gridCapacity > 0)
        #expect(family.gridColumns > 0)
    }

    /// The product requirement this table exists to satisfy: nine apps in the
    /// 2 × 2 widget.
    @Test("A small widget holds nine apps, three across")
    func smallHoldsNine() {
        #expect(WidgetFamily.systemSmall.gridCapacity == 9)
        #expect(WidgetFamily.systemSmall.gridColumns == 3)
    }

    /// The grid is handed the whole widget and takes its own margin off, so
///     `size` alone is not the footprint — the margin has to be counted too. A
///     grid that overflows its widget would silently drop its bottom row.
    @Test("The grid fits its widget at every size setting", arguments: Array(stride(from: 0.0, through: 1.0, by: 0.05)))
    func gridNeverOverflows(scale: Double) {
        let container = CGSize(width: 170, height: 170)
        let metrics = FolderGridMetrics(
            tileCount: WidgetFamily.systemSmall.gridCapacity,
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
}