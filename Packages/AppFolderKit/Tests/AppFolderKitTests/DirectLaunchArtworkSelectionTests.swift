import Testing
import WidgetKit
@testable import AppFolderKit

@Suite("Visible widget artwork")
struct DirectLaunchArtworkSelectionTests {
    @Test("Every dense overflow page keeps exact action identities and excludes offscreen artwork")
    func densePages() {
        guard #available(macOS 27.0, *) else { return }
        for family in [WidgetFamily.systemMedium, .systemLarge, .systemExtraLargePortrait] {
            for density in FolderDensity.allCases {
                let cells = FolderGrid.nine.cellCount(for: family, density: density)
                let capacity = cells - 1
                let layout = FolderExpansionLayout(family: family,
                                                   columns: FolderGrid.nine.columns(for: family, density: density),
                                                   cellCount: cells, appCount: 200 - capacity, reservesBackCell: true)
                let collapsed = DirectLaunchArtworkSelection.fullSizeArtworkIndices(
                    slotCount: 200, family: family, grid: .nine, isExpanded: false, page: 0, density: density)
                let visible = DirectLaunchArtworkSelection.visibleArtworkIndices(
                    slotCount: 200, family: family, grid: .nine, isExpanded: false, page: 0, density: density)
                #expect(collapsed == Set(0..<capacity))
                #expect(visible.subtracting(collapsed) == Set(capacity..<(capacity + 4)))
                var seen = Set<Int>()
                for page in 0..<layout.pageCount {
                    let current = DirectLaunchArtworkSelection.visibleArtworkIndices(
                        slotCount: 200, family: family, grid: .nine, isExpanded: true, page: page, density: density)
                    #expect(current == Set(layout.appIndices(onPage: page).map { $0 + capacity }))
                    #expect(current.isDisjoint(with: collapsed))
                    #expect(current.isDisjoint(with: seen))
                    #expect(current.count <= cells - 2)
                    seen.formUnion(current)
                }
                #expect(seen == Set(capacity..<200))
            }
        }
    }

    private func indices(
        _ count: Int, grid: FolderGrid, family: WidgetFamily = .systemSmall,
        expanded: Bool = false, page: Int = 0
    ) -> Set<Int> {
        DirectLaunchArtworkSelection.visibleArtworkIndices(
            slotCount: count, family: family, grid: grid, isExpanded: expanded, page: page
        )
    }

    private func fullSizeIndices(
        _ count: Int, grid: FolderGrid, family: WidgetFamily,
        expanded: Bool = false, page: Int = 0
    ) -> Set<Int> {
        DirectLaunchArtworkSelection.fullSizeArtworkIndices(
            slotCount: count, family: family, grid: grid, isExpanded: expanded, page: page
        )
    }

    @Test("One hundred actions retain only visible icons and four door miniatures")
    func collapsedBound() {
        #expect(indices(100, grid: .nine) == Set(0..<12))
        #expect(indices(100, grid: .four) == Set(0..<7))
    }

    @Test("Expanded pages retain absolute action indices without the collapsed apps")
    func expandedPageIdentity() {
        #expect(indices(100, grid: .nine, expanded: true) == Set(8..<15))
        #expect(indices(100, grid: .nine, expanded: true, page: 1) == Set(15..<22))
        #expect(indices(100, grid: .four, expanded: true) == Set(3..<5))
        #expect(indices(100, grid: .four, expanded: true, page: 1) == Set(5..<7))
    }

    @Test("A stale page clamps to real artwork rather than going blank")
    func stalePagesClamp() {
        for grid in FolderGrid.allCases {
            #expect(indices(100, grid: grid, expanded: true, page: .max) == [99])
            #expect(indices(100, grid: grid, expanded: true, page: -1)
                    == indices(100, grid: grid, expanded: true))
        }
    }

    @Test("Empty and non-overflow grids do not retain nonexistent photos")
    func shortConfigurations() {
        for grid in FolderGrid.allCases {
            #expect(indices(0, grid: grid).isEmpty)
            #expect(indices(-1, grid: grid, expanded: true).isEmpty)
            let capacity = grid.capacity(for: .systemSmall)
            #expect(indices(capacity, grid: grid) == Set(0..<capacity))
            #expect(indices(capacity, grid: grid, expanded: true, page: 99) == Set(0..<capacity))
            #expect(indices(capacity + 1, grid: grid) == Set(0...capacity))
            #expect(indices(capacity + 1, grid: grid, expanded: true) == [capacity])
        }
    }

    @Test("Paging eventually supplies every hidden action, once and only once")
    func allPagesReachAllPhotos() {
        for grid in FolderGrid.allCases {
            let capacity = grid.capacity(for: .systemSmall)
            let layout = FolderExpansionLayout(family: .systemSmall, grid: grid, appCount: 100 - capacity)
            var seen = Set<Int>()
            for page in 0..<layout.pageCount {
                let current = indices(100, grid: grid, expanded: true, page: page)
                #expect(seen.isDisjoint(with: current))
                #expect(current.count <= (grid == .nine ? 7 : 2))
                seen.formUnion(current)
            }
            #expect(seen == Set(capacity..<100))
        }
    }

    @Test("Collapsed full-size artwork excludes every overflow miniature across widget sizes")
    func fullSizeCollapsedTiles() {
        let configurations: [(WidgetFamily, FolderGrid, Int)] = [
            (.systemSmall, .four, 3), (.systemSmall, .nine, 8),
            (.systemMedium, .four, 9), (.systemMedium, .nine, 9),
            (.systemLarge, .four, 15), (.systemLarge, .nine, 15)
        ]
        for (family, grid, capacity) in configurations {
            let fullSize = fullSizeIndices(100, grid: grid, family: family, page: .max)
            let visible = indices(100, grid: grid, family: family)
            #expect(fullSize == Set(0..<capacity))
            #expect(fullSize.isSubset(of: visible))
            #expect(visible.subtracting(fullSize) == Set(capacity..<(capacity + 4)))

            // Even one overflow action lives inside the door until expanded.
            #expect(fullSizeIndices(capacity + 1, grid: grid, family: family) == fullSize)
            #expect(indices(capacity + 1, grid: grid, family: family).subtracting(fullSize) == [capacity])
        }
    }

    @Test("Expanded artwork promotes only the current page, including clamped final pages")
    func fullSizeExpandedPages() {
        let configurations: [(WidgetFamily, FolderGrid, Int, Int, Range<Int>)] = [
            (.systemSmall, .four, 3, 2, 99..<100),
            (.systemSmall, .nine, 8, 7, 99..<100),
            (.systemMedium, .four, 9, 8, 97..<100),
            (.systemMedium, .nine, 9, 8, 97..<100),
            (.systemLarge, .four, 15, 14, 99..<100),
            (.systemLarge, .nine, 15, 14, 99..<100)
        ]
        for (family, grid, capacity, pageSize, lastPage) in configurations {
            let first = fullSizeIndices(100, grid: grid, family: family, expanded: true, page: .min)
            let second = fullSizeIndices(100, grid: grid, family: family, expanded: true, page: 1)
            #expect(first == Set(capacity..<(capacity + pageSize)))
            #expect(second == Set((capacity + pageSize)..<(capacity + 2 * pageSize)))
            #expect(first.isDisjoint(with: second))
            #expect(fullSizeIndices(100, grid: grid, family: family, expanded: true, page: .max) == Set(lastPage))

            let layout = FolderExpansionLayout(family: family, grid: grid, appCount: 100 - capacity)
            var seen = Set<Int>()
            for page in 0..<layout.pageCount {
                let fullSize = fullSizeIndices(100, grid: grid, family: family, expanded: true, page: page)
                #expect(fullSize == indices(100, grid: grid, family: family, expanded: true, page: page))
                #expect(seen.isDisjoint(with: fullSize))
                seen.formUnion(fullSize)
            }
            #expect(seen == Set(capacity..<100))
        }
    }

    @Test("Short and invalid counts never create thumbnail-only or nonexistent full-size artwork")
    func fullSizeShortConfigurations() {
        for family in [WidgetFamily.systemSmall, .systemMedium, .systemLarge] {
            for grid in FolderGrid.allCases {
                let capacity = grid.capacity(for: family)
                for expanded in [false, true] {
                    for count in [Int.min, -1, 0, 1, capacity - 1, capacity] {
                        #expect(fullSizeIndices(count, grid: grid, family: family, expanded: expanded, page: .max)
                                == Set(0..<max(0, count)))
                    }
                }
                #expect(fullSizeIndices(capacity + 1, grid: grid, family: family, expanded: true, page: .max)
                        == [capacity])
            }
        }
    }
}
