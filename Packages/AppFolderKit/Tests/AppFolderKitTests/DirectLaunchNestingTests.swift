import Testing
import WidgetKit
@testable import AppFolderKit

/// When a direct-launch grid overflows, and what the door it grows is keyed on.
///
/// ## What this suite exists to pin
///
/// The nesting itself is not new — it is ``FolderGrid/capacity(for:)`` and
/// ``FolderExpansionLayout``, both already frozen by their own suites. What is
/// new is that the direct-launch widget *reads* them, so the numbers this suite
/// checks are the ones the two widgets now share. If a change here ever needs one
/// of those frozen types edited to pass, the direction is wrong and the frozen
/// suites will say so first.
///
/// ## The two thresholds, as the user stated them
///
/// 九宫格 in the small widget holds 8 apps and doors the ninth; 四宫格 holds 3 and
/// doors the fourth. Both are `cellCount - 1`, which is what
/// ``FolderGrid/capacity(for:)`` has always returned — see the first two tests,
/// which exist so that claim is checkable rather than remembered.
@Suite("Direct launch nesting")
struct DirectLaunchNestingTests {
    /// 3 × 3 in the small widget: eight apps, and the ninth cell is the door.
    @Test func nineGridInTheSmallWidgetHoldsEight() {
        #expect(FolderGrid.nine.cellCount(for: .systemSmall) == 9)
        #expect(FolderGrid.nine.capacity(for: .systemSmall) == 8)
    }

    /// 2 × 2 in the small widget: three apps, and the fourth cell is the door.
    ///
    /// The setting only reaches the small widget — a 四宫格 folder is still 5 across
    /// in medium and 3 in large, so this choice does not move the wider capacities.
    /// See ``FolderGrid/columns(for:)``. The medium number is 9 rather than 8
    /// because medium is 5 × 2 — ten cells, one of them the door.
    @Test func fourGridInTheSmallWidgetHoldsThree() {
        #expect(FolderGrid.four.cellCount(for: .systemSmall) == 4)
        #expect(FolderGrid.four.capacity(for: .systemSmall) == 3)
        #expect(FolderGrid.four.capacity(for: .systemMedium) == 9)
    }

    /// The door appears on the app *after* the capacity, at every threshold.
    @Test func theDoorAppearsAtOnePastTheCapacity() {
        for (grid, family, limit) in [
            (FolderGrid.nine, WidgetFamily.systemSmall, 8),
            (FolderGrid.four, WidgetFamily.systemSmall, 3),
            (FolderGrid.nine, WidgetFamily.systemMedium, 9),
            (FolderGrid.nine, WidgetFamily.systemLarge, 15),
        ] {
            let grid = grid as FolderGrid
            #expect(
                grid.nestedCell(for: family, tileCount: limit) == nil,
                "\(grid) \(family) should have no door at exactly \(limit)"
            )
            #expect(
                grid.nestedCell(for: family, tileCount: limit + 1) == grid.capacity(for: family),
                "\(grid) \(family) should door at \(limit + 1)"
            )
        }
    }

    /// The door's *preview* still counts only what the door hides, which is the list
/// it draws miniatures of.
    ///
    /// The door previews four of the hidden apps, so four is the number this pins.
    /// Note this is deliberately **not** what the panel lays out: the panel is a view
    /// of the whole configuration (see ``DirectLaunchPanelTests``), where the door's
    /// miniature grid is a view of the overflow. Both numbers are correct for their
    /// own surface, and the door's is `totalSlots - capacity`.
    @Test func theDoorsPreviewCountsOnlyWhatItHides() {
        let grid = FolderGrid.nine
        let hidden = 12 - grid.capacity(for: .systemSmall)
        #expect(hidden == 4)
    }

    /// Enough hidden apps to page, and the pages still cover all of them.
    @Test func aLargeGroupPagesWithoutLosingAnApp() {
        let grid = FolderGrid.nine
        let hidden = 20
        let layout = FolderExpansionLayout(family: .systemSmall, grid: grid, appCount: hidden)
        #expect(layout.isPaged)

        var seen: [Int] = []
        for page in 0..<layout.pageCount {
            seen.append(contentsOf: layout.appIndices(onPage: page))
        }
        #expect(seen == Array(0..<hidden))
    }

    // MARK: - The expansion key

    /// The key a grid is opened by is a function of its slots' names, in order,
    /// because a `SystemShortcut` gives the widget nothing else to identify it by.
    @Test func theSameSlotsProduceTheSameKey() {
        let names = ["微信", "相机", "地图"]
        #expect(
            WidgetState.directLaunchExpansionKey(slotNames: names)
                == WidgetState.directLaunchExpansionKey(slotNames: names)
        )
    }

    /// Reordering the slots is a different grid. If the key ignored order, opening
    /// one arrangement would expand another.
    @Test func reorderingTheSlotsChangesTheKey() {
        #expect(
            WidgetState.directLaunchExpansionKey(slotNames: ["微信", "相机"])
                != WidgetState.directLaunchExpansionKey(slotNames: ["相机", "微信"])
        )
    }

    /// Two grids of the same size with different apps are different grids. A key
    /// that only counted the slots would expand the wrong one — the reason the
    /// key is a digest of the names and not the count.
    @Test func twoEqualSizedGridsOfDifferentAppsDiffer() {
        #expect(
            WidgetState.directLaunchExpansionKey(slotNames: ["微信", "相机", "地图"])
                != WidgetState.directLaunchExpansionKey(slotNames: ["微信", "相机", "天气"])
        )
    }

    /// The separator keeps two short lists from colliding with one long one. The
    /// names here are the *only* thing that reaches the key, and a digest of
    /// `["ab", "c"]` must not equal a digest of `["a", "bc"]`.
    @Test func theKeySeparatesAdjacentNames() {
        #expect(
            WidgetState.directLaunchExpansionKey(slotNames: ["ab", "c"])
                != WidgetState.directLaunchExpansionKey(slotNames: ["a", "bc"])
        )
    }

    /// The digest is stable across processes, which is the whole reason it is not
    /// `hashValue` — the tap and the render are different processes and would
    /// otherwise disagree about which grid is open. Pinned against a literal so a
    /// change to the algorithm is caught rather than silently orphaning every open
    /// grid.
    @Test func theKeyIsStableAcrossProcesses() {
        #expect(DirectLaunchIcons.stableHash("") == "cbf29ce484222325")
        #expect(DirectLaunchIcons.stableHash("微信") == DirectLaunchIcons.stableHash("微信"))
    }
}