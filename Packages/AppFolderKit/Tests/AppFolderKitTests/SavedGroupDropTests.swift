import Foundation
import Testing
@testable import AppFolderKit

@Suite("Saved group atomic grid drops")
struct SavedGroupDropTests {
    @Test("Before anchors reorder in both directions by identity, with adjacent and self drops unchanged")
    func sameParentBefore() {
        let nodes = (0..<4).map { _ in GroupItem.action(name: "Same name") }
        let original = SavedGroup(name: "Grid", items: nodes)
        for (source, target, expected) in [(0, 3, [1, 2, 0, 3]), (3, 1, [0, 3, 1, 2]),
                                            (0, 1, [0, 1, 2, 3]), (2, 2, [0, 1, 2, 3])] {
            var group = original
            let outcome = group.applyDrop(request(group, nodes[source].id, .before(itemID: nodes[target].id)))
            #expect(outcome == (expected == [0, 1, 2, 3] ? .unchanged : .changed))
            #expect(group.items == expected.map { nodes[$0] })
            #expect(group.updatedAt == original.updatedAt)
        }
    }

    @Test("Cross-folder before and append preserve whole nodes and locate them after page counts change")
    func crossFolderAndPageChanges() throws {
        let source = GroupItem.website(name: "Site", url: "https://example.org/a%2Fb?q=A%2BB#part", browser: .appDefault)
        let target = GroupItem.action(name: "Target")
        let folder = GroupItem.folder(name: "Folder", children: [target])
        let others = (0..<3).map { GroupItem.action(name: "Other \($0)") }
        let original = SavedGroup(name: "Grid", items: [source] + others + [folder])
        #expect(SavedGroupPage(group: original, capacity: 4, usesIconNavigation: true).pageCount == 2)
        for destination in [SavedGroupDropTarget.before(itemID: target.id), .append(folderID: folder.id)] {
            var group = original
            let outcome = group.applyDrop(request(group, source.id, destination))
            #expect(outcome == .changed)
            #expect(group.items.map(\.id) == others.map(\.id) + [folder.id])
            let expected = destination == .before(itemID: target.id) ? [source, target] : [target, source]
            #expect(group.items(at: [folder.id]) == expected)
            let location = try #require(group.itemLocation(id: source.id))
            #expect(location.path == [folder.id] && expected[location.index] == source)
            let page = SavedGroupPage(group: group, capacity: 4, usesIconNavigation: true)
            #expect(page.pageCount == 1 && page.visibleItems.last?.id == folder.id)
            #expect(group.updatedAt == original.updatedAt)
            let back = group.applyDrop(request(group, source.id, .append(folderID: nil)))
            #expect(back == .changed && group.items.last == source)
            #expect(group.itemLocation(id: source.id) == .init(path: [], index: 4))
            #expect(group.items(at: [folder.id]) == [target])
        }
    }

    @Test("Explicit spacers swap into the source position without shifting other cells or increasing the node count")
    func spacerSwap() {
        let a = GroupItem.action(name: "A")
        let b = GroupItem.action(name: "B")
        let space = GroupItem.spacer()
        let c = GroupItem.action(name: "C")
        var group = SavedGroup(name: "Grid", items: [a, b, space, c])
        let stamp = group.updatedAt
        let outcome = group.applyDrop(request(group, a.id, .spacer(itemID: space.id)))
        #expect(outcome == .changed && group.items == [space, b, a, c])
        #expect(group.updatedAt == stamp)
        let selfDrop = group.applyDrop(request(group, space.id, .spacer(itemID: space.id)))
        #expect(selfDrop == .unchanged && group.items == [space, b, a, c])
    }

    @Test("Cross-folder swaps retain the complete subtree, browser choices, contacts, appearance and both artwork variants")
    func richSubtreeSwap() throws {
        let standard = try #require(FolderCoverAssetID(rawValue: String(repeating: "a", count: 64)))
        let dark = try #require(FolderCoverAssetID(rawValue: String(repeating: "b", count: 64)))
        let artwork = FolderCover(standard: standard, dark: dark)
        let contact = try #require(ContactTarget(operation: .message, number: "+12025550100"))
        let tree = GroupItem.folder(name: "Move", children: [
            .action(name: "Camera", displayName: "Photo"),
            .website(name: "Web", url: "https://example.org/?x=1#part", icon: artwork, browser: .appDefault),
            .folder(name: "Nested", children: [.contact(name: "Person", target: contact, icon: artwork)])
        ], folderCover: artwork, folderAppearance: .init(grid: .four, density: .spacious), folderPreviewGrid: .nine)
        let spacer = GroupItem.spacer()
        let untouched = GroupItem.action(name: "Keep")
        let destination = GroupItem.folder(name: "Destination", children: [spacer, untouched])
        let original = SavedGroup(name: "Grid", items: [tree, destination], updatedAt: Date(timeIntervalSince1970: 123_456.789))
        var group = original
        let result = group.applyDrop(request(group, tree.id, .spacer(itemID: spacer.id)))
        #expect(result == .changed && group.isValid)
        #expect(group.items[0] == spacer && group.items[1].children == [tree, untouched])
        #expect(group.coverAssetIDs == original.coverAssetIDs && group.updatedAt == original.updatedAt)
        let leaf = tree.children[2].children[0]
        #expect(group.itemLocation(id: leaf.id) == .init(path: [destination.id, tree.id, tree.children[2].id], index: 0))
    }

    @Test("A virtual empty target materializes only the source and skipped empty cells while keeping other positions")
    func vacantRootAndCrossPage() {
        let nodes = (0..<2).map { GroupItem.action(name: "Item \($0)") }
        let original = SavedGroup(name: "Grid", items: nodes)
        var group = original
        let outcome = group.applyDrop(request(group, nodes[0].id, .vacant(folderID: nil, capacity: 4, emptyOffset: 1)))
        #expect(outcome == .changed && group.items.count == 4)
        #expect(group.items[0].kind == .spacer && group.items[1] == nodes[1])
        #expect(group.items[2].kind == .spacer && group.items[3] == nodes[0])
        #expect(Set(group.items.map(\.id)).count == 4 && group.updatedAt == original.updatedAt)
        #expect(group.items[0].id != group.items[2].id)

        let pages = (0..<5).map { GroupItem.action(name: "Page item \($0)") }
        group = SavedGroup(name: "Pages", items: pages)
        let originalPage = SavedGroupPage(group: group, page: 1, capacity: 4, usesIconNavigation: true)
        #expect(originalPage.cells == [.previous, .item(pages[3]), .item(pages[4]), .empty])
        let crossPage = group.applyDrop(request(group, pages[0].id, .vacant(folderID: nil, capacity: 4, emptyOffset: 0)))
        #expect(crossPage == .changed && group.items[0].kind == .spacer)
        #expect(Array(group.items[1..<5]) == Array(pages[1..<5]))
        let last = SavedGroupPage(group: group, page: 1, capacity: 4, usesIconNavigation: true)
        #expect(last.pageCount == 2 && last.cells == [.previous, .item(pages[3]), .item(pages[4]), .item(pages[0])])
    }

    @Test("Virtual targets in empty and paged folders count only real empty cells, never parent or previous navigation")
    func vacantNested() throws {
        for count in [0, 13] {
            let source = GroupItem.action(name: "Source")
            let children = (0..<count).map { GroupItem.action(name: "Child \($0)") }
            let folder = GroupItem.folder(name: "Folder", children: children)
            var group = SavedGroup(name: "Grid", items: [source, folder])
            let offset = count == 0 ? 2 : 0
            let capacity = count == 0 ? 4 : 9
            let result = group.applyDrop(request(group, source.id, .vacant(folderID: folder.id, capacity: capacity, emptyOffset: offset)))
            #expect(result == .changed && group.items[0].kind == .spacer)
            let placed = try #require(group.items(at: [folder.id]))
            #expect(Array(placed.prefix(count)) == children && placed.last == source)
            #expect(placed.count == count + offset + 1)
            #expect(placed.dropFirst(count).dropLast().allSatisfy { $0.kind == .spacer })
            let last = SavedGroupPage(group: group, path: [folder.id], page: Int.max, capacity: capacity, usesIconNavigation: true)
            #expect(last.cells.first == .parent && last.cells.last == .item(source))
            if count == 13 { #expect(last.cells[1] == .previous && last.pageCount == 2) }
        }
    }

    @Test("Invalid targets and fabricated virtual cells reject atomically instead of clamping or falling back to root")
    func invalidTargets() {
        let source = GroupItem.action(name: "Source")
        let target = GroupItem.action(name: "Target")
        let spacer = GroupItem.spacer()
        let original = SavedGroup(name: "Grid", items: [source, target, spacer])
        var targets: [SavedGroupDropTarget] = [
            .before(itemID: UUID()), .before(itemID: spacer.id), .spacer(itemID: target.id), .spacer(itemID: UUID()),
            .append(folderID: UUID()), .append(folderID: target.id),
            .vacant(folderID: target.id, capacity: 4, emptyOffset: 0),
            .vacant(folderID: UUID(), capacity: 4, emptyOffset: 0)
        ]
        targets += [Int.min, 0, 3, 201, Int.max].map { .vacant(folderID: nil, capacity: $0, emptyOffset: 0) }
        targets += [-1, 1, Int.max].map { .vacant(folderID: nil, capacity: 4, emptyOffset: $0) }
        for target in targets {
            var group = original
            let result = group.applyDrop(request(group, source.id, target))
            #expect(result == .rejected(.invalidTarget) && group == original)
        }
        var full = SavedGroup(name: "Full", items: [source, target, spacer, .action(name: "Fourth")])
        let before = full
        let result = full.applyDrop(request(full, source.id, .vacant(folderID: nil, capacity: 4, emptyOffset: 0)))
        #expect(result == .rejected(.invalidTarget) && full == before)
    }

    @Test("Every destination form rejects a move into the source subtree before any source removal")
    func cyclePrevention() {
        let leaf = GroupItem.action(name: "Leaf")
        let space = GroupItem.spacer()
        let descendant = GroupItem.folder(name: "Descendant", children: [leaf, space])
        let source = GroupItem.folder(name: "Source", children: [descendant])
        let original = SavedGroup(name: "Grid", items: [source])
        for target in [SavedGroupDropTarget.before(itemID: leaf.id), .spacer(itemID: space.id),
                       .append(folderID: source.id), .append(folderID: descendant.id),
                       .vacant(folderID: descendant.id, capacity: 4, emptyOffset: 0)] {
            var group = original
            let result = group.applyDrop(request(group, source.id, target))
            #expect(result == .rejected(.cycle) && group == original)
        }
    }

    @Test("Depth overflow from a whole folder and spacer materialization beyond 200 nodes leave the original exact")
    func limitsAreAtomic() {
        let anchor = GroupItem.action(name: "Anchor")
        let spacer = GroupItem.spacer()
        let bottom = GroupItem.folder(name: "Level 4", children: [anchor, spacer])
        var nested = bottom
        for level in (1...3).reversed() { nested = .folder(name: "Level \(level)", children: [nested]) }
        let source = GroupItem.folder(name: "Move", children: [.action(name: "Keep")])
        let original = SavedGroup(name: "Depth", items: [nested, source])
        for target in [SavedGroupDropTarget.before(itemID: anchor.id), .spacer(itemID: spacer.id),
                       .append(folderID: bottom.id), .vacant(folderID: bottom.id, capacity: 4, emptyOffset: 0)] {
            var group = original
            let result = group.applyDrop(request(group, source.id, target))
            #expect(result == .rejected(.invalidResult) && group == original)
        }
        for (children, offset, allowed) in [(197, 0, true), (197, 1, false), (198, 0, false)] {
            let source = GroupItem.action(name: "Source")
            let folder = GroupItem.folder(name: "Many", children: (0..<children).map { .action(name: "Item \($0)") })
            let before = SavedGroup(name: "Budget", items: [source, folder])
            var group = before
            let result = group.applyDrop(request(group, source.id, .vacant(folderID: nil, capacity: 4, emptyOffset: offset)))
            #expect(result == (allowed ? .changed : .rejected(.invalidResult)))
            #expect(group.isValid)
            if !allowed { #expect(group == before) }
            else { #expect(group.items.last == source && group.items[0].kind == .spacer) }
        }
    }

    @Test("Group and revision identity reject stale edits; timestamp-only changes retain the intended tree operation")
    func staleRequests() {
        let a = GroupItem.action(name: "A")
        let b = GroupItem.action(name: "B")
        let original = SavedGroup(name: "Grid", items: [a, b])
        let operation = request(original, b.id, .before(itemID: a.id))
        var renamed = original
        renamed.items[0].name = "Edited"
        let current = renamed
        let stale = renamed.applyDrop(operation)
        #expect(stale == .rejected(.staleRevision) && renamed == current)
        var group = original
        let wrongGroup = SavedGroupDropRequest(groupID: UUID(), itemID: b.id, expectedRevision: group.revision, target: .before(itemID: a.id))
        #expect(group.applyDrop(wrongGroup) == .rejected(.wrongGroup) && group == original)
        #expect(group.applyDrop(request(group, UUID(), .append(folderID: nil))) == .rejected(.sourceNotFound) && group == original)
        group.updatedAt = original.updatedAt.addingTimeInterval(100)
        let stamp = group.updatedAt
        #expect(group.revision == original.revision)
        let changed = group.applyDrop(operation)
        #expect(changed == .changed && group.items == [b, a] && group.updatedAt == stamp)
        var invalid = original
        invalid.items.append(a)
        let invalidBefore = invalid
        #expect(invalid.itemLocation(id: a.id) == nil)
        #expect(invalid.applyDrop(operation) == .rejected(.invalidGroup) && invalid == invalidBefore)
        #expect(original.itemLocation(id: UUID()) == nil)
    }

    @Test("A committed drop is one exact undo step, while an adjacent no-op leaves the redo branch intact")
    func historyAndNoOp() {
        let a = GroupItem.action(name: "A")
        let b = GroupItem.action(name: "B")
        let space = GroupItem.spacer()
        let original = SavedGroup(name: "Grid", items: [a, b, space])
        var changed = original
        let result = changed.applyDrop(request(changed, a.id, .spacer(itemID: space.id)))
        #expect(result == .changed)
        var history = SavedGroupEditHistory()
        history.record(before: original, after: changed)
        let undone = history.undo(current: changed)
        #expect(undone == original && !history.canUndo && history.canRedo)
        var noOp = original
        let unchanged = noOp.applyDrop(request(noOp, a.id, .before(itemID: b.id)))
        #expect(unchanged == .unchanged && noOp == original)
        let recorded = history.record(before: original, after: noOp)
        #expect(!recorded && history.canRedo)
        #expect(history.redo(current: noOp) == changed)
    }

    private func request(_ group: SavedGroup, _ itemID: UUID, _ target: SavedGroupDropTarget) -> SavedGroupDropRequest {
        .init(groupID: group.id, itemID: itemID, expectedRevision: group.revision, target: target)
    }
}
