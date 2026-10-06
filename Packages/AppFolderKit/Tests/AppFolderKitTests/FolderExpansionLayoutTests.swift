import Testing
import WidgetKit

@testable import AppFolderKit

/// What an expanded folder looks like, page by page.
///
/// The type these check is pure, so almost everything worth knowing about it is
/// a property rather than an example: an app appears once, the back cell is
/// always where the eye starts, a next cell never leads nowhere. Those are
/// asserted as properties across every family, grid and count the app can
/// produce, because the failure they guard against — an app that cannot be
/// reached from any page — is exactly the kind that survives a hand-picked
/// example.
@Suite("Folder expansion layout")
struct FolderExpansionLayoutTests {
    /// The families the widget can actually be placed in, as the configuration
    /// declares them. `systemExtraLargePortrait` is included because the grid
    /// tables handle it and a future configuration change should not be the
    /// thing that discovers a divide-by-zero.
    private static let families: [WidgetFamily] = {
        var all: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
        // Gatekept rather than listed: the package typechecks on macOS 15, where
        // this case does not exist. The grid tables handle it, so a future
        // configuration change should not be what discovers a divide-by-zero.
        if #available(iOS 27.0, macOS 27.0, *) {
            all.append(.systemExtraLargePortrait)
        }
        return all
    }()

    /// Counts chosen around the boundaries, not spread evenly: the interesting
    /// ones are one below the page size, exactly it, one above, and something
    /// that needs several pages.
    private static func counts(for layout: (WidgetFamily, FolderGrid) -> Int) -> [Int] {
        [0, 1, 2, 3, 8, 9, 20]
    }

    private func layout(_ family: WidgetFamily, _ grid: FolderGrid, _ count: Int) -> FolderExpansionLayout {
        FolderExpansionLayout(family: family, grid: grid, appCount: count)
    }

    // MARK: - Page size

    /// The reserved-cell arithmetic, stated as the two branches the type
    /// documents rather than re-derived from `pageSize` — re-deriving it here
    /// would make the test agree with a bug.
    @Test("Page size is the cell count less the cells that are reserved", arguments: families)
    func pageSize(family: WidgetFamily) {
        for grid in FolderGrid.allCases {
            let cells = grid.cellCount(for: family)
            for count in [0, cells - 2, cells - 1, cells, cells + 1, 40] {
                let layout = layout(family, grid, count)
                let expected = count <= cells - 1 ? cells - 1 : cells - 2
                #expect(layout.pageSize == expected, "\(family) \(grid) \(count)")
                #expect(layout.pageSize >= 1, "a page with no room for an app")
            }
        }
    }

    /// The invariant that makes the two-branch definition safe. If the paging
    /// branch could ever produce one page, a folder would show a next cell that
    /// leads to itself.
    @Test("A paged folder always has somewhere to page to", arguments: families)
    func pagingAlwaysHasASecondPage(family: WidgetFamily) {
        for grid in FolderGrid.allCases {
            let cells = grid.cellCount(for: family)
            for count in [cells, cells + 1, cells + 12, 40] {
                let layout = layout(family, grid, count)
                #expect(layout.isPaged)
                #expect(layout.pageCount >= 2, "\(family) \(grid) \(count) paged to one page")
            }
        }
    }

    /// A folder that fits — including exactly at capacity — is one page with no
    /// next cell. This is the case the uniform "always reserve" rule would get
    /// wrong by hiding an app behind a next cell that goes nowhere.
    @Test("A folder that fits is one page", arguments: families)
    func fittingFolderIsOnePage(family: WidgetFamily) {
        for grid in FolderGrid.allCases {
            let cells = grid.cellCount(for: family)
            let layout = layout(family, grid, cells - 1)
            #expect(!layout.isPaged)
            #expect(layout.pageCount == 1)
            #expect(layout.role(forCell: layout.nextCell, onPage: 0) == .empty)
        }
    }

    /// An empty folder is still one page, not zero. A caller that had to
    /// special-case the empty folder would be the caller that divides by it.
    @Test("An empty folder is one page and no apps")
    func emptyFolder() {
        let layout = layout(.systemSmall, .nine, 0)
        #expect(layout.pageCount == 1)
        #expect(layout.appIndices(onPage: 0).isEmpty)
    }

    // MARK: - Cells

    @Test("The back cell is the first cell on every page", arguments: families)
    func backIsAlwaysFirst(family: WidgetFamily) {
        for grid in FolderGrid.allCases {
            for count in [0, 5, 40] {
                let layout = layout(family, grid, count)
                #expect(layout.backCell == 0)
                for page in 0..<layout.pageCount {
                    #expect(layout.role(forCell: 0, onPage: page) == .back)
                }
            }
        }
    }

    /// The next cell sits exactly where the collapsed grid put its door.
    ///
    /// Not a coincidence to be left implicit: it is what lets the expand tap
    /// change one cell's role and leave the other eight untouched, which is what
    /// makes the reload beat read as a state change.
    @Test("The next cell is the cell the collapsed door was in", arguments: families)
    func nextIsWhereTheDoorWas(family: WidgetFamily) {
        for grid in FolderGrid.allCases {
            let cells = grid.cellCount(for: family)
            let layout = layout(family, grid, cells + 4)
            #expect(layout.isPaged)
            #expect(layout.nextCell == grid.capacity(for: family), "\(family) \(grid)")
            #expect(layout.nextCell == layout.cellCount - 1)
        }
    }

    /// A next cell only appears before the last page. On the last page that cell
    /// is empty, so the way back is the back cell rather than a dead end.
    @Test("Next appears on every page but the last", arguments: families)
    func nextOnlyBeforeTheEnd(family: WidgetFamily) {
        let layout = layout(family, .nine, 40)
        for page in 0..<layout.pageCount {
            let role = layout.role(forCell: layout.nextCell, onPage: page)
            if page < layout.pageCount - 1 {
                #expect(role == .next, "page \(page)")
            } else {
                #expect(role == .empty, "page \(page)")
            }
        }
    }

    /// The next cell is never an app, on any page of any folder. It is the one
    /// cell a mistyped index would land on, and an app there would be an app
    /// drawn as "more".
    @Test("The next cell never holds an app", arguments: families)
    func nextCellIsNeverAnApp(family: WidgetFamily) {
        for grid in FolderGrid.allCases {
            for count in [0, 5, 9, 40] {
                let layout = layout(family, grid, count)
                for page in 0..<layout.pageCount {
                    if case .app = layout.role(forCell: layout.nextCell, onPage: page) {
                        Issue.record("\(family) \(grid) \(count) page \(page): an app in the next cell")
                    }
                }
            }
        }
    }

    // MARK: - The whole folder, across pages

    /// No app is lost and none is drawn twice: across all pages, the app indices
    /// are exactly `0..<appCount`, each once, in order.
    ///
    /// This is the property that justifies pagination at all. Losing an app is
    /// the exact failure the door exists to prevent, and it is invisible from any
    /// single page.
    @Test("Every app appears exactly once, across all pages", arguments: families)
    func everyAppAppearsOnce(family: WidgetFamily) {
        for grid in FolderGrid.allCases {
            for count in [0, 1, 3, 8, 9, 10, 21, 40] {
                let layout = layout(family, grid, count)
                var seen: [Int] = []
                for page in 0..<layout.pageCount {
                    seen.append(contentsOf: layout.appIndices(onPage: page))
                }
                #expect(seen == Array(0..<count), "\(family) \(grid) \(count)")
            }
        }
    }

    /// The role a cell reports and the index the page assigns agree. Two ways of
    /// asking the same question must not disagree, or the drawn cell and the tile
    /// it opens would be different apps.
    @Test("Roles and page indices agree", arguments: families)
    func rolesAndIndicesAgree(family: WidgetFamily) {
        for grid in FolderGrid.allCases {
            for count in [0, 5, 10, 40] {
                let layout = layout(family, grid, count)
                for page in 0..<layout.pageCount {
                    let indices = layout.appIndices(onPage: page)
                    for cell in 0..<layout.cellCount {
                        switch layout.role(forCell: cell, onPage: page) {
                        case .app(let index):
                            #expect(indices.contains(index), "\(family) \(grid) \(count) cell \(cell)")
                            #expect(layout.tileIndex(forCell: cell, onPage: page) == index)
                            #expect(cell >= 1 && cell <= layout.pageSize)
                        case .back, .next, .empty:
                            #expect(layout.tileIndex(forCell: cell, onPage: page) == nil)
                        }
                    }
                }
            }
        }
    }

    /// The number of app cells on a page is the number of apps it holds — no
    /// stray cell reporting an app the page does not have.
    @Test("A page draws exactly the apps it holds", arguments: families)
    func appCellCountMatches(family: WidgetFamily) {
        for grid in FolderGrid.allCases {
            for count in [0, 7, 12, 40] {
                let layout = layout(family, grid, count)
                for page in 0..<layout.pageCount {
                    let appCells = (0..<layout.cellCount).filter { cell in
                        if case .app = layout.role(forCell: cell, onPage: page) { return true }
                        return false
                    }
                    #expect(appCells.count == layout.appIndices(onPage: page).count,
                            "\(family) \(grid) \(count) page \(page)")
                }
            }
        }
    }

    // MARK: - Stale pages

    /// The reader clamps, because the writer cannot know the family. A stored
    /// page past the end draws the last page; a negative one draws the first.
    @Test("An out-of-range page is clamped, not honoured", arguments: families)
    func stalePagesClamp(family: WidgetFamily) {
        let layout = layout(family, .nine, 20)
        #expect(layout.clampedPage(-5) == 0)
        #expect(layout.clampedPage(0) == 0)
        #expect(layout.clampedPage(layout.pageCount - 1) == layout.pageCount - 1)
        #expect(layout.clampedPage(layout.pageCount + 99) == layout.pageCount - 1)
        // A clamped page still answers coherently rather than trapping.
        #expect(layout.appIndices(onPage: 999) == layout.appIndices(onPage: layout.pageCount - 1))
        #expect(layout.role(forCell: 0, onPage: -3) == .back)
    }

    /// `pageIndex(forTile:)` is the inverse of `appIndices(onPage:)`, which is
    /// what lets the editor say where an app will land.
    @Test("A tile's page is the page that draws it", arguments: families)
    func pageIndexInvertsAppIndices(family: WidgetFamily) {
        for grid in FolderGrid.allCases {
            for count in [1, 5, 10, 40] {
                let layout = layout(family, grid, count)
                for page in 0..<layout.pageCount {
                    for index in layout.appIndices(onPage: page) {
                        #expect(layout.pageIndex(forTile: index) == page,
                                "\(family) \(grid) \(count) tile \(index)")
                    }
                }
            }
        }
    }

    /// Out-of-grid cells are empty rather than a crash. The view builds cells
    /// from the metrics' rectangle, so a mismatch between the two tables would
    /// arrive here as an out-of-range cell.
    @Test("A cell outside the grid is empty")
    func outsideCellsAreEmpty() {
        let layout = layout(.systemSmall, .nine, 20)
        #expect(layout.role(forCell: -1, onPage: 0) == .empty)
        #expect(layout.role(forCell: layout.cellCount, onPage: 0) == .empty)
    }
}