import Foundation
import Testing
import WidgetKit
@testable import AppFolderKit

@Suite("Saved-group icon navigation")
struct SavedGroupIconPaginationTests {
    @Test("Every family and density preserves all 200 items exactly once within the fixed grid")
    func allFamiliesAndDensities() throws {
        var configurations: [(WidgetFamily, FolderGrid, FolderDensity)] = [(.systemSmall, .four, .standard), (.systemSmall, .nine, .standard)]
        var families: [WidgetFamily] = [.systemMedium, .systemLarge, .systemExtraLarge]
        if #available(macOS 27.0, *) { families.append(.systemExtraLargePortrait) }
        for family in families {
            for density in FolderDensity.allCases { configurations.append((family, .nine, density)) }
        }
        for (family, grid, density) in configurations {
            let capacity = grid.cellCount(for: family, density: density)
            let sizes = Set([0, 1, capacity - 2, capacity - 1, capacity, capacity + 1, 2 * capacity, 199, 200])
            for nested in [false, true] {
                for count in sizes where count >= 0 && count <= (nested ? 199 : 200) {
                    let expected = leaves(count)
                    let folder = GroupItem.folder(name: "Nested", children: expected)
                    let group = SavedGroup(name: "Grid", items: nested ? [folder] : expected,
                                           appearance: .init(grid: grid, density: density))
                    #expect(group.isValid)
                    let path = nested ? [folder.id] : []
                    let first = SavedGroupPageLayout(group: group, path: path, family: family,
                                                    useGroupAppearance: true, widgetStyle: .init())
                    var seen: [UUID] = []
                    for index in 0..<first.page.pageCount {
                        let current = SavedGroupPageLayout(group: group, path: path, page: index, family: family,
                                                          useGroupAppearance: true, widgetStyle: .init())
                        #expect(current.page.capacity == capacity && current.cells.count == capacity)
                        #expect(current.cells == current.page.cells)
                        let content = items(current.cells)
                        #expect(content == current.page.visibleItems)
                        seen += content.map(\.id)
                        #expect(current.cells.filter { $0 == .parent }.count == (nested ? 1 : 0))
                        #expect(current.cells.filter { $0 == .previous }.count == (index > 0 ? 1 : 0))
                        #expect(current.cells.filter { $0 == .next }.count == (index + 1 < first.page.pageCount ? 1 : 0))
                        if nested { #expect(current.cells.first == .parent) }
                        if index > 0 { #expect(current.cells[nested ? 1 : 0] == .previous) }
                        if current.page.hasNextPage { #expect(current.cells.last == .next && !content.isEmpty) }
                        if count > 0 { #expect(!content.isEmpty) }
                    }
                    #expect(seen == expected.map(\.id))
                    #expect(Set(seen).count == count)
                }
            }
        }
    }

    @Test("Four-cell first, middle and last pages use their actual remaining budgets")
    func fourCellBoundaries() {
        let rootItems = leaves(8)
        let root = SavedGroup(name: "Root", items: rootItems)
        #expect(page(root, 0).cells == rootItems.prefix(3).map(SavedGroupGridCell.item) + [.next])
        #expect(page(root, 1).cells == [.previous] + rootItems[3..<5].map(SavedGroupGridCell.item) + [.next])
        #expect(page(root, 2).cells == [.previous] + rootItems[5..<8].map(SavedGroupGridCell.item))
        #expect(page(root, 0).pageCount == 3)

        let childItems = leaves(6)
        let folder = GroupItem.folder(name: "Child", children: childItems)
        let nested = SavedGroup(name: "Nested", items: [folder])
        #expect(page(nested, 0, path: [folder.id]).cells == [.parent, .item(childItems[0]), .item(childItems[1]), .next])
        #expect(page(nested, 1, path: [folder.id]).cells == [.parent, .previous, .item(childItems[2]), .next])
        #expect(page(nested, 2, path: [folder.id]).cells == [.parent, .previous, .item(childItems[3]), .next])
        #expect(page(nested, 3, path: [folder.id]).cells == [.parent, .previous, .item(childItems[4]), .item(childItems[5])])
        #expect(page(nested, 3, path: [folder.id]).pageCount == 4)
    }

    @Test("Fits and empty folders never introduce an unnecessary next page")
    func fitAndEmpty() {
        for capacity in [4, 9, 10, 16, 21, 49, 77] {
            let exact = SavedGroup(name: "Exact", items: leaves(capacity))
            let root = SavedGroupPage(group: exact, capacity: capacity, usesIconNavigation: true)
            #expect(root.pageCount == 1 && root.visibleItems.count == capacity)
            #expect(root.cells.allSatisfy { if case .item = $0 { return true }; return false })
            let child = GroupItem.folder(name: "Exact child", children: leaves(capacity - 1))
            let group = SavedGroup(name: "Group", items: [child])
            let childPage = SavedGroupPage(group: group, path: [child.id], capacity: capacity, usesIconNavigation: true)
            #expect(childPage.pageCount == 1 && childPage.visibleItems.count == capacity - 1)
            #expect(childPage.cells.first == .parent && !childPage.cells.contains(.next))
            let empty = GroupItem.folder(name: "Empty")
            let emptyPage = SavedGroupPage(group: SavedGroup(name: "Root", items: [empty]), path: [empty.id],
                                           page: Int.max, capacity: capacity, usesIconNavigation: true)
            #expect(emptyPage.page == 0 && emptyPage.pageCount == 1 && emptyPage.visibleItems.isEmpty)
            #expect(emptyPage.cells == [.parent] + Array(repeating: .empty, count: capacity - 1))
        }
        let emptyRoot = SavedGroupPage(group: SavedGroup(name: "Empty"), capacity: 4, usesIconNavigation: true)
        #expect(emptyRoot.cells == Array(repeating: .empty, count: 4))
    }

    @Test("A deepest return uses the parent's navigation cells instead of index divided by capacity")
    func deepestParentAtLimit() throws {
        let final = GroupItem.folder(name: "Final", children: [.action(name: "Only")], folderAppearance: .init(grid: .nine))
        let outer = GroupItem.folder(name: "Four", children: leaves(197) + [final], folderAppearance: .init(grid: .four))
        let group = SavedGroup(name: "Root", items: [outer], appearance: .init(grid: .nine))
        #expect(group.isValid)
        let child = SavedGroupPageLayout(group: group, path: [outer.id, final.id], family: .systemSmall,
                                        useGroupAppearance: true, widgetStyle: .init())
        let back = try #require(child.parentNavigation)
        #expect(back.path == [outer.id] && back.page == 195)
        let parent = SavedGroupPageLayout(group: group, path: back.path, page: back.page, family: .systemSmall,
                                         useGroupAppearance: true, widgetStyle: .init())
        #expect(parent.page.visibleItems.last?.id == final.id)
        #expect(parent.cells.prefix(2) == [.parent, .previous])
        #expect(parent.parentNavigation == .init(path: [], page: 0))
    }

    @Test("Different root and nested densities return to the same folder in every supported family")
    func parentDensityAndManualStyle() throws {
        var families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
        if #available(macOS 27.0, *) { families.append(.systemExtraLargePortrait) }
        for family in families {
            let inner = GroupItem.folder(name: "Dense", folderAppearance: .init(grid: .nine, density: .dense))
            let outer = GroupItem.folder(name: "Spacious", children: leaves(82) + [inner],
                                         folderAppearance: .init(grid: .four, density: .spacious))
            let group = SavedGroup(name: "Root", items: leaves(83) + [outer], appearance: .init(grid: .nine, density: .dense))
            #expect(group.isValid)
            for useGroup in [false, true] {
                let manual = FolderStyle(grid: .nine, density: .standard)
                let current = SavedGroupPageLayout(group: group, path: [outer.id, inner.id], family: family,
                                                  useGroupAppearance: useGroup, widgetStyle: manual)
                let back = try #require(current.parentNavigation)
                let parent = SavedGroupPageLayout(group: group, path: back.path, page: back.page, family: family,
                                                 useGroupAppearance: useGroup, widgetStyle: manual)
                #expect(parent.page.visibleItems.contains { $0.id == inner.id })
                let rootBack = try #require(parent.parentNavigation)
                let root = SavedGroupPageLayout(group: group, path: rootBack.path, page: rootBack.page, family: family,
                                               useGroupAppearance: useGroup, widgetStyle: manual)
                #expect(root.page.visibleItems.contains { $0.id == outer.id })
                if !useGroup { #expect(current.style == manual && parent.style == manual && root.style == manual) }
            }
        }
    }

    @Test("Stale paths reset to root while page and extreme capacity inputs remain bounded")
    func staleAndDefensiveInputs() {
        let folder = GroupItem.folder(name: "Child", children: leaves(199))
        let group = SavedGroup(name: "Root", items: [folder])
        let stale = SavedGroupPage(group: group, path: [UUID()], page: Int.max, capacity: 4, usesIconNavigation: true)
        #expect(stale.path.isEmpty && stale.page == 0 && stale.pageCount == 1)
        #expect(stale.cells == [.item(folder), .empty, .empty, .empty])
        for capacity in [Int.min, -1, 0, 1, 2, 3] {
            let first = SavedGroupPage(group: group, path: [folder.id], page: Int.min, capacity: capacity, usesIconNavigation: true)
            let last = SavedGroupPage(group: group, path: [folder.id], page: Int.max, capacity: capacity, usesIconNavigation: true)
            #expect(first.capacity == 4 && first.page == 0 && first.visibleItems.count == 2)
            #expect(last.capacity == 4 && last.page == first.pageCount - 1 && last.visibleItems.count == 2)
            #expect(last.cells.count == 4 && last.cells.first == .parent && !last.cells.contains(.next))
        }
        let huge = SavedGroupPage(group: group, path: [folder.id], capacity: Int.max, usesIconNavigation: true)
        #expect(huge.capacity == SavedGroup.maximumItems && huge.cells.count == SavedGroup.maximumItems && huge.pageCount == 1)
        let legacy = SavedGroupPage(group: group, path: [folder.id], capacity: Int.max)
        #expect(legacy.capacity == Int.max && legacy.visibleItems == folder.children && legacy.pageCount == 1)
    }

    @Test("Spacers, folders and website leaves retain their identity and are never mistaken for navigation")
    func mixedItemsAndLegacyBudget() {
        let expected: [GroupItem] = [.spacer(), .website(name: "Site", url: "https://example.com"),
                                     .folder(name: "Empty"), .action(name: "Calendar", displayName: "Visible"), .spacer()]
        let group = SavedGroup(name: "Mixed", items: expected)
        let first = page(group, 0)
        let second = page(group, 1)
        #expect(items(first.cells) + items(second.cells) == expected)
        #expect(second.cells.last == .empty)
        let legacy = SavedGroupPage(group: group, capacity: 4)
        #expect(legacy.visibleItems == Array(expected.prefix(4)) && legacy.pageCount == 2)
        #expect(legacy.cells == expected.prefix(4).map(SavedGroupGridCell.item))
    }

    private func leaves(_ count: Int) -> [GroupItem] { (0..<count).map { .action(name: "Action \($0)") } }
    private func items(_ cells: [SavedGroupGridCell]) -> [GroupItem] {
        cells.compactMap { if case .item(let item) = $0 { return item }; return nil }
    }
    private func page(_ group: SavedGroup, _ page: Int, path: [UUID] = []) -> SavedGroupPage {
        .init(group: group, path: path, page: page, capacity: 4, usesIconNavigation: true)
    }
}
