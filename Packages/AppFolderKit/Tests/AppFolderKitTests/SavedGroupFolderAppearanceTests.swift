import Foundation
import Testing
import WidgetKit
@testable import AppFolderKit

@Suite("Saved folder appearance and navigation")
struct SavedGroupFolderAppearanceTests {
    @Test("An override replaces a whole appearance and nil inherits the closest ancestor")
    func inheritance() throws {
        let root = SavedGroupAppearance(grid: .four, plate: .gradient, tintHex: "#123456", density: .spacious)
        let parentStyle = SavedGroupAppearance(grid: .nine, showsTitles: false, density: .dense, backButtonStyle: .folder)
        let lastStyle = SavedGroupAppearance(iconSize: .large, plate: .solid, tintHex: "#ABCDEF", backButtonStyle: .turnUpLeft)
        let last = GroupItem.folder(name: "Last", folderAppearance: lastStyle)
        let inherited = GroupItem.folder(name: "Inherited", children: [last])
        let parent = GroupItem.folder(name: "Parent", children: [inherited], folderAppearance: parentStyle)
        let sibling = GroupItem.folder(name: "Sibling")
        let group = SavedGroup(name: "Group", items: [parent, sibling, .action(name: "Maps")], appearance: root)
        #expect(group.resolvedAppearance(at: []) == root)
        #expect(group.resolvedAppearance(at: [parent.id]) == parentStyle)
        #expect(group.resolvedAppearance(at: [parent.id, inherited.id]) == parentStyle)
        #expect(group.resolvedAppearance(at: [parent.id, inherited.id, last.id]) == lastStyle)
        #expect(group.resolvedAppearance(at: [sibling.id]) == root)
        #expect(group.appearanceOverride(at: [parent.id, inherited.id]) == nil)
        #expect(group.appearanceOverride(at: [parent.id]) == parentStyle)
        #expect(group.hasFolderAppearanceOverrides)
        for path in [[last.id], [parent.id, sibling.id], [group.items[2].id], Array(repeating: parent.id, count: 5)] {
            #expect(group.resolvedAppearance(at: path) == nil)
        }
        let legacy = SavedGroup(name: "Default", items: [sibling])
        #expect(legacy.resolvedAppearance(at: [sibling.id]) == .default)
        #expect(!legacy.hasFolderAppearanceOverrides)
    }

    @Test("A strict scope edit cannot overwrite the root when its folder path becomes stale")
    func atomicScopeEdits() {
        let child = GroupItem.folder(name: "Child")
        let folder = GroupItem.folder(name: "Parent", children: [child])
        var group = SavedGroup(name: "Group", items: [folder, .action(name: "Maps")], appearance: .init(grid: .four))
        let parentStyle = SavedGroupAppearance(density: .dense, backButtonStyle: .folder)
        let setParent = group.setAppearance(parentStyle, at: [folder.id])
        #expect(setParent && group.appearance?.grid == .four)
        #expect(group.resolvedAppearance(at: [folder.id, child.id]) == parentStyle)
        let before = group
        for path in [[child.id], [folder.id, UUID()], [group.items[1].id]] {
            let changed = group.setAppearance(.default, at: path)
            #expect(!changed && group == before)
        }
        var invalid = parentStyle
        invalid.tintHex = "invalid"
        let invalidFolder = group.setAppearance(invalid, at: [folder.id])
        let invalidRoot = group.setAppearance(invalid, at: [])
        #expect(!invalidFolder && !invalidRoot && group == before)
        let inherited = group.setAppearance(nil, at: [folder.id])
        #expect(inherited && group.resolvedAppearance(at: [folder.id, child.id]) == group.resolvedAppearance)
        #expect(!group.hasFolderAppearanceOverrides)
        let clearedRoot = group.setAppearance(nil, at: [])
        #expect(clearedRoot && group.resolvedAppearance(at: [folder.id]) == .default)
    }

    @Test("Returning through differently sized small folders uses each parent's own capacity")
    func parentPage() throws {
        let inner = GroupItem.folder(name: "Nine", children: leaves(12), folderAppearance: .init(grid: .nine))
        let outer = GroupItem.folder(name: "Four", children: leaves(8) + [inner], folderAppearance: .init(grid: .four))
        let group = SavedGroup(name: "Root nine", items: leaves(10) + [outer], appearance: .init(grid: .nine))
        let current = layout(group, [outer.id, inner.id], page: 1)
        #expect(current.page.capacity == 9 && current.page.visibleItems.count == 5)
        #expect(current.parentNavigation == .init(path: [outer.id], page: 6))
        let parent = layout(group, [outer.id], page: current.parentNavigation?.page ?? -1)
        #expect(parent.page.capacity == 4 && parent.page.visibleItems.count == 2)
        #expect(parent.page.visibleItems.last?.id == inner.id)
        #expect(parent.parentNavigation == .init(path: [], page: 1))
        let root = layout(group, [], page: parent.parentNavigation?.page ?? -1)
        #expect(root.page.visibleItems.contains { $0.id == outer.id })

        let manual = FolderStyle(grid: .nine, backButtonStyle: .turnUpLeft)
        let disabled = SavedGroupPageLayout(group: group, path: [outer.id, inner.id], page: 1,
                                            family: .systemSmall, useGroupAppearance: false, widgetStyle: manual)
        #expect(disabled.style == manual && disabled.parentNavigation == .init(path: [outer.id], page: 1))
        #expect(SavedGroupPageLayout(group: group, path: [outer.id], family: .systemSmall,
                                    useGroupAppearance: false, widgetStyle: manual).style == manual)
    }

    @Test("Density-changing folders retain the page containing their entry in every larger family")
    func largerParentPages() {
        var families = [WidgetFamily.systemMedium, .systemLarge]
        if #available(macOS 27.0, *) { families.append(.systemExtraLargePortrait) }
        for family in families {
            let rootAppearance = SavedGroupAppearance(density: .spacious)
            let childAppearance = SavedGroupAppearance(density: .dense)
            let capacity = rootAppearance.grid.cellCount(for: family, density: rootAppearance.density)
            let child = GroupItem.folder(name: "Dense", children: leaves(80), folderAppearance: childAppearance)
            let group = SavedGroup(name: "Spacious", items: leaves(capacity + 1) + [child], appearance: rootAppearance)
            #expect(group.isValid)
            let current = SavedGroupPageLayout(group: group, path: [child.id], page: 100,
                                               family: family, useGroupAppearance: true, widgetStyle: .init())
            #expect(current.page.capacity == childAppearance.grid.cellCount(for: family, density: .dense))
            #expect(current.parentNavigation == .init(path: [], page: 1))
            let parent = SavedGroupPageLayout(group: group, page: 1, family: family,
                                              useGroupAppearance: true, widgetStyle: .init())
            #expect(parent.page.visibleItems.contains { $0.id == child.id })
        }
    }

    @Test("Invalid paths reset page and style together while valid paths clamp the page")
    func stalePaths() {
        let child = GroupItem.folder(name: "Four", children: leaves(5), folderAppearance: .init(grid: .four))
        let group = SavedGroup(name: "Nine", items: leaves(12) + [child], appearance: .init(grid: .nine, backButtonStyle: .folder))
        let stale = layout(group, [UUID()], page: 99)
        #expect(stale.page.path.isEmpty && stale.page.page == 0 && stale.parentNavigation == nil)
        #expect(stale.page.capacity == 9 && stale.style == group.resolvedAppearance.style)
        let valid = layout(group, [child.id], page: 99)
        #expect(valid.page.path == [child.id] && valid.page.page == 2 && valid.page.capacity == 4)
    }

    @Test("Navigation keys preserve legacy bytes and isolate enabled nested overrides without including a path")
    func navigationKeys() {
        let folder = GroupItem.folder(name: "Nested", folderPreviewGrid: .nine)
        var group = SavedGroup(name: "Group", items: [folder])
        func legacy(_ group: SavedGroup) -> String { "base|group:\(group.id.uuidString)|\(group.revision)" }
        #expect(group.navigationKey(baseKey: "base", useGroupAppearance: false) == legacy(group))
        #expect(group.navigationKey(baseKey: "base", useGroupAppearance: true) == legacy(group))
        group.items[0].folderAppearance = .init(grid: .four)
        let off = group.navigationKey(baseKey: "base", useGroupAppearance: false)
        let on = group.navigationKey(baseKey: "base", useGroupAppearance: true)
        #expect(off == legacy(group) && on == off + "|folder-appearance:on")
        #expect(layout(group, []).style.grid == .nine && layout(group, [folder.id]).style.grid == .four)
        #expect(group.navigationKey(baseKey: "base", useGroupAppearance: true) == on)
    }

    @Test("Missing new fields preserve exact legacy folder bytes and the layout revision")
    func legacyBytes() throws {
        let data = Data(##"{"appearance":{"density":"dense","grid":"nine","iconSize":"medium","plate":"automatic","showsTitles":true,"tintHex":"#0A84FF"},"id":"00000000-0000-0000-0000-000000000001","items":[{"children":[{"children":[],"id":"00000000-0000-0000-0000-000000000003","kind":"action","name":"Maps"}],"id":"00000000-0000-0000-0000-000000000002","kind":"folder","name":"Nested"}],"name":"Legacy","updatedAt":0}"##.utf8)
        let group = try JSONDecoder().decode(SavedGroup.self, from: data)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(try encoder.encode(group) == data)
        #expect(group.revision == "aebc4390b5150bb34fd13c461558c24a4347ee222bbd6dbbadc3e2dba9a8b657")
        #expect(group.items[0].folderAppearance == nil && group.items[0].folderPreviewGrid == nil)
        #expect(group.resolvedAppearance.backButtonStyle == .chevronUp)
        var changed = group
        changed.items[0].folderPreviewGrid = .nine
        #expect(changed.revision != group.revision)
        changed = group
        changed.appearance?.backButtonStyle = .folder
        #expect(changed.revision != group.revision)
    }

    @Test("Invalid folder fields and return symbols are rejected without damaging the saved group")
    func validationAndStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("folder-style-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SavedGroupRepository(directory: directory)
        let group = SavedGroup(name: "Valid", items: [.folder(name: "Custom", folderAppearance: .init(tintHex: " aabbcc ", backButtonStyle: .folder), folderPreviewGrid: .nine)])
        #expect(store.save(group))
        let loaded = try #require(SavedGroupRepository(directory: directory).group(id: group.id))
        #expect(loaded.items[0].folderAppearance?.tintHex == "#AABBCC")
        #expect(loaded.items[0].folderAppearance?.backButtonStyle == .folder && loaded.items[0].folderPreviewGrid == .nine)
        var invalid = loaded
        invalid.items[0].folderAppearance?.tintHex = "broken"
        #expect(!store.save(invalid) && store.group(id: group.id) == loaded)
        for leaf in [GroupItem.action(name: "Maps"), .website(name: "Site", url: "https://example.com"), .spacer()] {
            var bad = leaf
            bad.folderAppearance = .default
            #expect(!SavedGroup(name: "Bad", items: [bad]).isValid)
            bad.folderAppearance = nil
            bad.folderPreviewGrid = .nine
            #expect(!SavedGroup(name: "Bad", items: [bad]).isValid)
            for key in ["folderAppearance", "folderPreviewGrid"] {
                var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(leaf)) as? [String: Any])
                object[key] = NSNull()
                let data = try JSONSerialization.data(withJSONObject: object)
                #expect(throws: (any Error).self) { try JSONDecoder().decode(GroupItem.self, from: data) }
            }
        }
        let invalidSymbols: [Any] = ["unknown", NSNull(), 1]
        for value in invalidSymbols {
            var appearance = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(SavedGroupAppearance())) as? [String: Any])
            appearance["backButtonStyle"] = value
            let data = try JSONSerialization.data(withJSONObject: appearance)
            #expect(throws: (any Error).self) { try JSONDecoder().decode(SavedGroupAppearance.self, from: data) }
        }
    }

    @Test("Folder moves and undo restore whole overrides and node-specific nine-leaf miniatures")
    func moveAndUndo() throws {
        let websites = (0..<5).map { GroupItem.website(name: "Site \($0)", url: "https://example.com/\($0)") }
        let actions = (0..<7).map { GroupItem.action(name: "Action \($0)", displayName: "Alias") }
        let child = GroupItem.folder(name: "Moving", children: [.spacer()] + websites + [.folder(name: "Inner", children: actions)],
                                      folderAppearance: .init(grid: .four, backButtonStyle: .turnUpLeft), folderPreviewGrid: .nine)
        let destination = GroupItem.folder(name: "Destination", folderAppearance: .init(density: .dense))
        let before = SavedGroup(name: "Move", items: [child, destination])
        #expect(child.previewLeafItems.map(\.id) == (websites + Array(actions.prefix(4))).map(\.id))
        #expect(child.previewActionNames == Array(actions.prefix(4)).map(\.name))
        var after = before
        let moved = after.move(itemID: child.id, to: [destination.id])
        #expect(moved && after.items(at: [destination.id])?.first == child)
        #expect(after.resolvedAppearance(at: [destination.id, child.id]) == child.folderAppearance)
        var history = SavedGroupEditHistory()
        history.record(before: before, after: after)
        #expect(history.undo(current: after) == before)
        #expect(history.redo(current: before) == after)
        #expect(MiniGridDensity.maximumCapacity == 4)
    }

    @Test("Nine-leaf previews respect the fourth folder level and 200-node traversal bound")
    func miniatureBounds() {
        let expected = leaves(9)
        var deepest = GroupItem.folder(name: "4", children: expected)
        for depth in (1...3).reversed() { deepest = .folder(name: "\(depth)", children: [deepest]) }
        deepest.folderPreviewGrid = .nine
        #expect(SavedGroup(name: "Deep", items: [deepest]).isValid)
        #expect(deepest.previewLeafItems.map(\.id) == expected.map(\.id))
        let spaces = (0..<190).map { _ in GroupItem.spacer() }
        let bounded = GroupItem.folder(name: "Full", children: spaces + expected, folderPreviewGrid: .nine)
        #expect(SavedGroup(name: "Full", items: [bounded]).isValid)
        #expect(bounded.previewLeafItems.map(\.id) == expected.map(\.id))
        let tooMany = GroupItem.folder(name: "Too many", children: spaces + [.spacer()] + expected, folderPreviewGrid: .nine)
        #expect(tooMany.previewLeafItems.count == 8)
    }

    private func leaves(_ count: Int) -> [GroupItem] { (0..<count).map { .action(name: "Action \($0)") } }

    private func layout(_ group: SavedGroup, _ path: [UUID], page: Int = 0) -> SavedGroupPageLayout {
        .init(group: group, path: path, page: page, family: .systemSmall, useGroupAppearance: true, widgetStyle: .init())
    }
}
