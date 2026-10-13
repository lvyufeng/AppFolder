import Testing
import WidgetKit

@testable import AppFolderKit

/// The layout the direct-launch **panel** is drawn from: the apps the door was
/// hiding, with cell 0 given up to 返回.
///
/// ## Why this is a second suite and not more cases in the first
///
/// ``FolderExpansionLayout`` is one type serving two callers that differ in how many
/// apps they lay out and, at the edges, how many cells. That makes the panel's own
/// arithmetic — the cell floor in particular — invisible from the door's tests, and
/// the panel is where a wrong cell count silently moves every app.
///
/// ## The shape this pins, and the bug behind it
///
/// The panel draws `entry.hiddenSlots`, not the whole configuration. It used to draw
/// everything: on a small widget with three apps hidden behind the door, the first
/// page was the *identical* eight faces the Home Screen already showed, plus a 更多 —
/// so the tap that opened the panel changed one cell, and the apps the door promised
/// took a second tap to reach. Anything that puts the visible apps back on page one
/// would return that bug, so the count the panel lays out is asserted here rather
/// than left to the view.
///
/// ## What is *not* testable here, and why that is not a gap
///
/// The step from a panel index to the `SystemShortcut` that gets run —
/// `entry.shortcuts[panelSlots[index].id]` — lives in the widget target, where
/// `DirectLaunchSlot` is, and there is no widget test target. What can be pinned here
/// is the half that makes it safe: the layout addresses the list it was given as an
/// exact, ordered `0..<count`, with no gap and nothing twice. The other half is that
/// the widget passes `entry.hiddenSlots` — the overflow, in configuration order — and
/// takes the index from the slot's own `id` rather than computing an offset, which is
/// a one-line read in the view. Device check: tap the panel's first app tile and
/// confirm it opens the ninth app of the collapsed grid.
@Suite("Direct launch panel layout")
struct DirectLaunchPanelTests {
    private static let counts = [0, 1, 3, 8, 9, 10, 18, 40]

    /// A 3 × 3 small panel, built the way ``DirectLaunchPanelView`` builds it: nine
    /// cells, floored at two only for the un-measured `1 × 1` case.
    private func panel(_ count: Int) -> FolderExpansionLayout {
        FolderExpansionLayout(
            family: .systemSmall, columns: 3, cellCount: 9, appCount: count, reservesBackCell: true
        )
    }

    // MARK: - The way back

    /// Cell 0 is 返回 on every page, at every count — including an empty panel, so
    /// the exit is in the same place whether there is anything to show or not.
    @Test func cellZeroIsAlwaysTheWayBack() {
        for count in Self.counts {
            let layout = panel(count)
            for page in 0..<max(1, layout.pageCount) {
                #expect(layout.role(forCell: 0, onPage: page) == .back, "count \(count) page \(page)")
            }
        }
    }

    /// Apps start at cell 1, never at cell 0.
    @Test func appsStartAfterTheBackCell() {
        let layout = panel(3)
        #expect(layout.firstAppCell == 1)
        #expect(layout.role(forCell: 1, onPage: 0) == .app(0))
    }

    // MARK: - The floor that keeps a short panel from collapsing

    /// A short overflow still fills the whole rectangle: the cells are kept and left
    /// blank rather than dropped, so the panel does not change shape with the count.
    ///
    /// The bug this guards is the one the panel just came back from — a three-app
    /// overflow drawing in the top-left of a widget-sized rectangle.
    @Test func aShortPanelKeepsTheFullGrid() {
        let layout = panel(3)
        #expect(layout.cellCount == 9)
        #expect(layout.pageCount == 1)
        // Three apps, then blanks — not a shrunken grid.
        #expect(layout.appIndices(onPage: 0) == 0..<3)
        #expect(layout.role(forCell: 4, onPage: 0) == .empty)
    }

    /// The floor is two, not the shape: a caller with no room to measure still gets a
/// panel where an app can appear beside the way back, and the shape governs
/// everywhere else.
    @Test func theCellCountFloorIsTwo() {
        let unmeasured = FolderExpansionLayout(
            family: .systemSmall, columns: 1, cellCount: 2, appCount: 1, reservesBackCell: true
        )
        #expect(unmeasured.cellCount == 2)
        #expect(unmeasured.role(forCell: 0, onPage: 0) == .back)
        #expect(unmeasured.role(forCell: 1, onPage: 0) == .app(0))
    }

    // MARK: - Coverage

    /// No app lost, none drawn twice — the property the widget's correctness rests
    /// on, stated across pages rather than page by page.
    @Test func pagesCoverEveryAppExactlyOnce() {
        for count in Self.counts {
            let layout = panel(count)
            var seen: [Int] = []
            for page in 0..<layout.pageCount {
                seen.append(contentsOf: layout.appIndices(onPage: page))
            }
            #expect(seen == Array(0..<count), "count \(count)")
        }
    }

    /// The layout addresses its list as an exact ordered range, which is what lets
    /// the view index the slot array by it with no translation.
    @Test func appIndicesAreAnExactOrderedRange() {
        for count in Self.counts {
            let layout = panel(count)
            for page in 0..<layout.pageCount {
                let indices = layout.appIndices(onPage: page)
                #expect(indices.lowerBound >= 0)
                #expect(indices.upperBound <= count)
                let drawn = (0..<layout.cellCount).compactMap { layout.tileIndex(forCell: $0, onPage: page) }
                #expect(drawn == Array(indices), "count \(count) page \(page)")
            }
        }
    }

    /// With the way back reserved, a page holds one fewer than the grid — eight on a
/// nine-cell panel. Eight apps are one page; the ninth is the first app that pages.
    @Test func aPageHoldsOneFewerThanTheGrid() {
        let fits = panel(8)
        #expect(fits.pageSize == 8)
        #expect(fits.pageCount == 1)
        #expect(fits.isPaged == false)

        let overflows = panel(9)
        #expect(overflows.isPaged)
        #expect(overflows.pageCount == 2)
    }

    /// A paged panel always has somewhere to go — the invariant that keeps a single
    /// page from drawing a 更多 that leads to itself.
    @Test func pagingAlwaysHasASecondPage() {
        for count in [9, 10, 18, 40] {
            let layout = panel(count)
            #expect(layout.isPaged, "count \(count)")
            #expect(layout.pageCount >= 2, "count \(count)")
        }
    }

    /// An app index is never outside the list, whatever the count or page — the
    /// out-of-range case that would trap the view.
    @Test func appIndicesStayInsideTheList() {
        for count in Self.counts {
            let layout = panel(count)
            for page in -2...(layout.pageCount + 2) {
                for cell in 0..<layout.cellCount {
                    if case .app(let index) = layout.role(forCell: cell, onPage: page) {
                        #expect(index >= 0 && index < max(count, 1),
                                "count \(count) page \(page) cell \(cell) -> \(index)")
                    }
                }
            }
        }
    }

    /// Empty is still a page with a way back. A caller that had to special-case zero
    /// would be the caller that forgets to.
    @Test func anEmptyPanelIsStillAPageWithAWayBack() {
        let layout = panel(0)
        #expect(layout.pageCount == 1)
        #expect(layout.appIndices(onPage: 0).isEmpty)
        #expect(layout.role(forCell: 0, onPage: 0) == .back)
    }
}