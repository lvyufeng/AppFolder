import Foundation
import Testing
@testable import AppFolderKit

@Suite("Saved group layouts")
struct SavedGroupTests {
    @Test("References follow names when configured action order changes")
    func bindingsFollowConfiguredNames() {
        let first = SavedGroupBinding(actionNames: ["Camera", " Maps ", "Café"])
        let reordered = SavedGroupBinding(actionNames: ["Café", "Camera", "Maps"])
        #expect(first.resolve("MAPS") == .matched(index: 1))
        #expect(reordered.resolve(" maps ") == .matched(index: 2))
        #expect(first.resolve("Cafe\u{301}") == .matched(index: 2))
        #expect(first.resolve("missing") == .missing)
    }

    @Test("Same-name system actions are conflicts, never positional guesses")
    func ambiguousBindings() {
        let binding = SavedGroupBinding(actionNames: ["Maps", " maps ", "Camera", "", " "])
        #expect(binding.resolve("Maps") == .ambiguous)
        #expect(binding.resolve("Camera") == .matched(index: 2))
        #expect(binding.resolve("") == .missing)
        #expect(binding.resolve("Unknown") == .missing)
    }

    @Test("All 200 configured actions retain their system indices, including position 101")
    func fullConfigurationBindings() {
        let names = (1...200).map { "Action \($0)" }
        let group = SavedGroup(name: "Full configuration", items: names.map { .action(name: $0) })
        let binding = SavedGroupBinding(actionNames: names)

        #expect(group.isValid)
        #expect(group.allActionNames.count == 200)
        #expect(binding.resolve("Action 101") == .matched(index: 100))
        #expect(binding.resolve("Action 200") == .matched(index: 199))
        for (index, name) in group.allActionNames.enumerated() {
            #expect(binding.resolve(name) == .matched(index: index))
        }

        let reordered = SavedGroupBinding(actionNames: Array(names.reversed()))
        #expect(reordered.resolve("Action 101") == .matched(index: 99))
        #expect(reordered.resolve("Action 200") == .matched(index: 0))
    }

    @Test("Duplicate names beyond former configuration limits still block launching", arguments: [100, 200])
    func lateDuplicateBindings(index: Int) {
        let names = ["Pay"] + (1..<index).map { "Other \($0)" } + [" pay "]
        let binding = SavedGroupBinding(actionNames: names)
        #expect(binding.resolve("Pay") == .ambiguous)
        #expect(binding.resolve("Other \(index - 1)") == .matched(index: index - 1))
    }

    @Test("Repeated layout leaves need only one configured system action")
    func repeatedReferences() {
        let group = SavedGroup(name: "Everyday", items: [
            .action(name: "Maps"),
            .folder(name: "Travel", children: [.action(name: "Camera"), .action(name: "maps")]),
            .spacer(),
        ])
        #expect(group.allActionNames == ["Maps", "Camera"])
        let binding = SavedGroupBinding(actionNames: group.allActionNames)
        #expect(binding.resolve("Maps") == binding.resolve("maps"))
        #expect(group.isValid)
    }

    @Test("Folders preserve their own page contents and ancestor relationships")
    func nestedPaths() {
        let nested = GroupItem.folder(name: "Tools", children: [.action(name: "Calculator")])
        let folder = GroupItem.folder(name: "Work", children: [.action(name: "Mail"), nested])
        let group = SavedGroup(name: "Everyday", items: [.action(name: "Maps"), folder])

        #expect(group.items(at: [folder.id, nested.id]) == nested.children)
        #expect(group.items(at: [nested.id]) == nil, "a descendant cannot skip its parent")
        let page = SavedGroupPage(group: group, path: [folder.id, nested.id], page: 0, capacity: 4)
        #expect(page.visibleItems == nested.children)
        #expect(page.folderName == "Tools")
        #expect(page.parentPath == [folder.id])
        #expect(page.canGoBack)
    }

    @Test("Stale folder paths reset to root rather than opening an unrelated folder")
    func stalePaths() {
        let folder = GroupItem.folder(name: "Old", children: [.action(name: "Mail")])
        let group = SavedGroup(name: "Current", items: (0..<20).map { .action(name: "App \($0)") })
        let page = SavedGroupPage(group: group, path: [folder.id], page: 4, capacity: 4)
        #expect(page.path.isEmpty)
        #expect(page.page == 0)
        #expect(page.visibleItems.map(\.name) == ["App 0", "App 1", "App 2", "App 3"])
        #expect(page.folderName == "Current")
        #expect(page.parentPath == nil)
    }

    @Test("Every node remains reachable across pages", arguments: [4, 9])
    func allNodesReachable(capacity: Int) {
        let group = SavedGroup(name: "All", items: (0..<SavedGroup.maximumItems).map { .action(name: "App \($0)") })
        let first = SavedGroupPage(group: group, capacity: capacity)
        let ids = (0..<first.pageCount).flatMap {
            SavedGroupPage(group: group, page: $0, capacity: capacity).visibleItems.map(\.id)
        }
        #expect(ids == group.items.map(\.id))
        #expect(Set(ids).count == group.items.count)
        #expect(!first.hasPreviousPage)
        #expect(first.hasNextPage)
        let last = SavedGroupPage(group: group, page: Int.max, capacity: capacity)
        #expect(!last.hasNextPage)
        #expect(last.hasPreviousPage)
        #expect(last.page == first.pageCount - 1)
    }

    @Test("Empty and extreme pagination inputs are clamped without overflow")
    func paginationBounds() {
        let empty = SavedGroupPage(group: SavedGroup(name: "Empty"), page: Int.max, capacity: 0)
        #expect(empty.page == 0)
        #expect(empty.pageCount == 1)
        #expect(empty.visibleItems.isEmpty)
        #expect(empty.capacity == 1)

        let group = SavedGroup(name: "Items", items: [.spacer(), .action(name: "Mail")])
        #expect(SavedGroupPage(group: group, page: -1, capacity: 4).page == 0)
        #expect(SavedGroupPage(group: group, page: Int.max, capacity: Int.max).visibleItems == group.items)
    }

    @Test("Limits bound folder depth and total nodes, with room for 200 actions")
    func sizeLimits() {
        #expect(SavedGroup(name: "Full", items: (0..<100).map { .action(name: "App \($0)") }).isValid)
        #expect(SavedGroup(name: "Full", items: (0..<200).map { .action(name: "App \($0)") }).isValid)
        #expect(!SavedGroup(name: "Too many", items: (0..<201).map { .action(name: "App \($0)") }).isValid)

        var nodes = [GroupItem.action(name: "Bottom")]
        for depth in 1...SavedGroup.maximumDepth { nodes = [.folder(name: "Level \(depth)", children: nodes)] }
        #expect(SavedGroup(name: "Allowed", items: nodes).isValid)
        #expect(!SavedGroup(name: "Too deep", items: [.folder(name: "Another", children: nodes)]).isValid)
    }

    @Test("Node identities and shapes cannot alias or hide children")
    func nodeValidation() {
        let action = GroupItem.action(name: "Mail")
        #expect(!SavedGroup(name: "Duplicate IDs", items: [action, action]).isValid)
        #expect(!SavedGroup(name: "Bad leaf", items: [.init(kind: .action, name: "Mail", children: [.action(name: "Maps")])]).isValid)
        #expect(!SavedGroup(name: "Bad space", items: [.init(kind: .spacer, name: "Hidden")]).isValid)
        #expect(!SavedGroup(name: "Empty folder name", items: [.folder(name: " ")]).isValid)
        #expect(!SavedGroup(name: "Line\nbreak").isValid)
        #expect(!SavedGroup(name: String(repeating: "a", count: 81)).isValid)
        #expect(!SavedGroup(name: "Big scalar", items: [.action(name: "A" + String(repeating: "\u{301}", count: 400))]).isValid)
    }

    @Test("Replacement is atomic for stale paths and invalid IDs")
    func replaceItems() {
        let action = GroupItem.action(name: "Mail")
        let folder = GroupItem.folder(name: "Work", children: [action])
        var group = SavedGroup(name: "Group", items: [folder])
        let original = group
        let mutationResult1 = !group.replaceItems([action], at: [UUID()])
        #expect(mutationResult1)
        #expect(group == original)
        let mutationResult2 = !group.replaceItems([action, action], at: [folder.id])
        #expect(mutationResult2)
        #expect(group == original)
        let replacement = GroupItem.action(name: "Calendar")
        let mutationResult3 = group.replaceItems([replacement], at: [folder.id])
        #expect(mutationResult3)
        #expect(group.items(at: [folder.id]) == [replacement])
    }

    @Test("Moves preserve node identity and reject cycles or stale destinations")
    func moveItems() {
        let nested = GroupItem.folder(name: "Nested", children: [.action(name: "Mail")])
        let left = GroupItem.folder(name: "Left", children: [nested])
        let right = GroupItem.folder(name: "Right")
        var group = SavedGroup(name: "Group", items: [left, right])
        let original = group
        let mutationResult4 = !group.move(itemID: left.id, to: [left.id, nested.id])
        #expect(mutationResult4)
        #expect(group == original)
        let mutationResult5 = !group.move(itemID: nested.id, to: [UUID()])
        #expect(mutationResult5)
        #expect(group == original)
        let mutationResult6 = group.move(itemID: nested.id, to: [right.id])
        #expect(mutationResult6)
        #expect(group.items(at: [left.id]) == [])
        #expect(group.items(at: [right.id]) == [nested])
        let mutationResult7 = group.move(itemID: nested.id, to: [], at: 0)
        #expect(mutationResult7)
        #expect(group.items.first == nested)
    }

    @Test("Moves reject depth overflow and invalid insertion without deleting the source")
    func invalidMoveIsAtomic() {
        let bottom = GroupItem.folder(name: "Depth 4")
        let level3 = GroupItem.folder(name: "Depth 3", children: [bottom])
        let level2 = GroupItem.folder(name: "Depth 2", children: [level3])
        let level1 = GroupItem.folder(name: "Depth 1", children: [level2])
        let movable = GroupItem.folder(name: "Move me", children: [.action(name: "Mail")])
        var group = SavedGroup(name: "Group", items: [level1, movable])
        let original = group
        let mutationResult8 = !group.move(itemID: movable.id, to: [level1.id, level2.id, level3.id, bottom.id])
        #expect(mutationResult8)
        #expect(group == original)
        let mutationResult9 = !group.move(itemID: movable.id, to: [], at: 100)
        #expect(mutationResult9)
        #expect(group == original)
        let mutationResult10 = group.move(itemID: movable.id, to: [], at: 0)
        #expect(mutationResult10)
        #expect(group.items.map(\.id) == [movable.id, level1.id])
    }

    @Test("Layout revisions are stable across coding and ignore timestamp-only changes")
    func revision() throws {
        var group = SavedGroup(name: "Group", items: [.action(name: "Maps"), .spacer()])
        let before = group.revision
        group.updatedAt = group.updatedAt.addingTimeInterval(10)
        #expect(group.revision == before)
        let roundTrip = try JSONDecoder().decode(SavedGroup.self, from: JSONEncoder().encode(group))
        #expect(roundTrip.revision == before)
        group.items.swapAt(0, 1)
        #expect(group.revision != before)
    }

    @Test("Decoding cannot bypass tree validation")
    func decodingValidation() throws {
        var invalid = SavedGroup(name: "Invalid", items: [.action(name: "Mail")])
        invalid.items.append(invalid.items[0])
        let data = try JSONEncoder().encode(invalid)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(SavedGroup.self, from: data) }
    }
}

@Suite("Saved group storage")
struct SavedGroupStoreTests {
    @Test("Independent groups survive reopening with layout and identity intact")
    func durableGroups() throws {
        try withRepository { repository, directory in
            let first = SavedGroup(name: "Work", items: [.folder(name: "Tools", children: [.action(name: "Mail")])])
            let second = SavedGroup(name: "Home", items: [.spacer(), .action(name: "Maps")])
            #expect(repository.save(first))
            #expect(repository.save(second))
            let reopened = SavedGroupRepository(directory: directory)
            #expect(reopened.group(id: first.id) == first)
            #expect(reopened.group(id: second.id) == second)
            #expect(Set(reopened.all.map(\.id)) == [first.id, second.id])
            #expect(reopened.revision == repository.revision)
        }
    }

    @Test("Renaming a group keeps its ID and leaves other groups unchanged")
    func renameAndRemove() throws {
        try withRepository { repository, _ in
            var first = SavedGroup(name: "Work", items: [.action(name: "Mail")])
            let second = SavedGroup(name: "Home", items: [.action(name: "Maps")])
            #expect(repository.save(first))
            #expect(repository.save(second))
            let oldRevision = repository.revision
            #expect(repository.save(first))
            #expect(repository.revision == oldRevision)
            first.name = "  Office  "
            #expect(repository.save(first))
            #expect(repository.group(id: first.id)?.name == "Office")
            #expect(repository.revision != oldRevision)
            #expect(repository.group(id: second.id) == second)
            #expect(repository.remove(id: first.id))
            #expect(repository.remove(id: first.id))
            #expect(repository.group(id: first.id) == nil)
            #expect(repository.all == [second])
        }
    }

    @Test("Invalid drafts cannot overwrite a valid group")
    func failedSavePreservesPriorGroup() throws {
        try withRepository { repository, _ in
            let valid = SavedGroup(name: "Work", items: [.action(name: "Mail")])
            #expect(repository.save(valid))
            var invalid = valid
            invalid.items.append(valid.items[0])
            #expect(!repository.save(invalid))
            #expect(repository.group(id: valid.id) == valid)
        }
    }

    @Test("Unavailable or unwritable storage reports failure without a private fallback")
    func storageFailure() throws {
        let group = SavedGroup(name: "Work")
        let unavailable = SavedGroupRepository(directory: nil)
        #expect(!unavailable.isAvailable)
        #expect(!unavailable.save(group))
        #expect(!unavailable.remove(id: group.id))
        #expect(unavailable.all.isEmpty)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Group-file-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("existing file".utf8).write(to: url)
        #expect(!SavedGroupRepository(directory: url).save(group))
        #expect(try Data(contentsOf: url) == Data("existing file".utf8))
    }

    @Test("Corrupt, oversized and misidentified records are ignored")
    func untrustedRecords() throws {
        try withRepository { repository, directory in
            let valid = SavedGroup(name: "Work")
            #expect(repository.save(valid))
            let corruptID = UUID()
            try Data("not JSON".utf8).write(to: directory.appendingPathComponent(corruptID.uuidString.lowercased() + ".json"))
            let oversizedID = UUID()
            try Data(repeating: 0, count: SavedGroupRepository.maximumFileBytes + 1)
                .write(to: directory.appendingPathComponent(oversizedID.uuidString.lowercased() + ".json"))
            let mismatchedID = UUID()
            let encoder = JSONEncoder()
            try encoder.encode(valid).write(to: directory.appendingPathComponent(mismatchedID.uuidString.lowercased() + ".json"))
            #expect(repository.group(id: corruptID) == nil)
            #expect(repository.group(id: oversizedID) == nil)
            #expect(repository.group(id: mismatchedID) == nil)
            #expect(repository.all == [valid])
        }
    }

    @Test("Names never become storage paths")
    func opaqueFilenames() throws {
        try withRepository { repository, directory in
            let group = SavedGroup(name: "../../outside")
            #expect(repository.save(group))
            let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            #expect(files == [group.id.uuidString.lowercased() + ".json"])
            #expect(repository.group(id: group.id)?.name == "../../outside")
        }
    }

    private func withRepository(_ body: (SavedGroupRepository, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AppFolder-groups-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(SavedGroupRepository(directory: directory), directory)
    }
}
