import Foundation
import Testing
@testable import AppFolderKit

@Suite("Saved group edit history")
struct SavedGroupEditHistoryTests {
    @Test("Undoing a folder deletion restores its whole tree and every identity")
    func restoresDeletedTree() throws {
        let before = fixture()
        let removed = before.items[1]
        var after = before
        after.items.remove(at: 1)
        var history = SavedGroupEditHistory()
        let recorded = history.record(before: before, after: after)
        #expect(recorded)
        let undone = history.undo(current: after)
        let restored = try #require(undone)
        #expect(restored == before)
        #expect(restored.items[1] == removed)
        #expect(restored.items[1].children[0].children[0].displayTitle == "Meetings")
        #expect(history.redo(current: restored) == after)
    }

    @Test("Batch addition, reordering and cross-folder moves undo and redo in order")
    func structuralEdits() throws {
        let original = fixture()
        var added = original
        added.items += [.action(name: "Weather"), .action(name: "Notes", displayName: "Ideas")]
        var reordered = added
        reordered.items.swapAt(0, reordered.items.count - 1)
        var moved = reordered
        let left = moved.items[1]
        let right = moved.items[2]
        let movable = left.children[0]
        let didMove = moved.move(itemID: movable.id, to: [right.id])
        #expect(didMove)
        #expect(moved.items(at: [right.id])?.last == movable)

        var history = SavedGroupEditHistory()
        let states = [original, added, reordered, moved]
        for index in 1..<states.count {
            history.record(before: states[index - 1], after: states[index])
        }
        var current = moved
        for expected in states.dropLast().reversed() {
            let undone = history.undo(current: current)
            current = try #require(undone)
            #expect(current == expected)
        }
        #expect(!history.canUndo)
        #expect(history.undo(current: current) == nil)
        for expected in states.dropFirst() {
            let redone = history.redo(current: current)
            current = try #require(redone)
            #expect(current == expected)
        }
        #expect(!history.canRedo)
        #expect(history.redo(current: current) == nil)
    }

    @Test("Raw invalid names, action bindings, aliases and appearance remain exact snapshots", arguments: ["", "  \n "])
    func preservesRawDraft(rawName: String) throws {
        var before = fixture()
        before.name = rawName
        var after = before
        after.name = "  My week  "
        after.items[0].name = "Calendar"
        after.items[0].displayName = "  Next meeting  "
        after.appearance = .init(grid: .nine, showsTitles: false, iconSize: .small,
                                 plate: .solid, tintHex: "#123456")
        after.appearance?.tintHex = " abcdef "
        after.updatedAt = before.updatedAt.addingTimeInterval(1)
        #expect(!before.isValid)
        var history = SavedGroupEditHistory()
        let recorded = history.record(before: before, after: after)
        #expect(recorded)
        #expect(history.undo(current: after) == before)
        #expect(history.redo(current: before) == after)
        #expect(after.items[0].id == before.items[0].id)
    }

    @Test("Failed operations and no-ops do not consume history or discard redo")
    func ignoresNoOps() throws {
        let before = SavedGroup(name: "Full", items: (0..<SavedGroup.maximumItems).map {
            .action(name: "Action \($0)")
        })
        var after = before
        after.items.swapAt(0, after.items.count - 1)
        var history = SavedGroupEditHistory()
        let noOpRecorded = history.record(before: before, after: before)
        #expect(!noOpRecorded)
        #expect(!history.canUndo)
        history.record(before: before, after: after)
        #expect(history.undo(current: after) == before)
        #expect(history.canRedo)
        var failed = before
        let didAdd = failed.replaceItems(failed.items + [.action(name: "Extra 1"), .action(name: "Extra 2")], at: [])
        #expect(!didAdd)
        let failedRecorded = history.record(before: before, after: failed)
        #expect(!failedRecorded)
        #expect(history.canRedo)
        #expect(history.redo(current: before) == after)
        #expect(history.undo(current: after) == before)
        #expect(!history.canUndo)
    }

    @Test("A new edit after undo replaces the redo branch")
    func branchesAfterUndo() {
        let a = fixture()
        let b = renamed(a, "B")
        let c = renamed(a, "C")
        var history = SavedGroupEditHistory()
        history.record(before: a, after: b)
        #expect(history.undo(current: b) == a)
        history.record(before: a, after: c)
        #expect(!history.canRedo)
        #expect(history.redo(current: c) == nil)
        #expect(history.undo(current: c) == a)
        #expect(history.redo(current: a) == c)
    }

    @Test("Capacity retains only recent steps and stays bounded across undo and redo")
    func capacityBound() throws {
        let a = fixture()
        let states = [a, renamed(a, "B"), renamed(a, "C"), renamed(a, "D")]
        var history = SavedGroupEditHistory(capacity: 2)
        for index in 1..<states.count {
            history.record(before: states[index - 1], after: states[index])
        }
        #expect(history.undo(current: states[3]) == states[2])
        #expect(history.undo(current: states[2]) == states[1])
        #expect(history.undo(current: states[1]) == nil)
        #expect(history.redo(current: states[1]) == states[2])
        #expect(history.redo(current: states[2]) == states[3])
        #expect(history.redo(current: states[3]) == nil)
        #expect(SavedGroupEditHistory().capacity == 50)
        for capacity in [0, -1] {
            var disabled = SavedGroupEditHistory(capacity: capacity)
            let recorded = disabled.record(before: states[0], after: states[1])
            #expect(recorded)
            #expect(!disabled.canUndo && !disabled.canRedo)
        }
    }

    @Test("Continuous edits with the same key coalesce, and ending a gesture creates a boundary")
    func continuousCoalescing() throws {
        let a = fixture()
        let b = renamed(a, "B")
        let c = renamed(a, "C")
        let d = renamed(a, "D")
        var history = SavedGroupEditHistory()
        history.record(before: a, after: b, coalescingKey: "name")
        history.record(before: b, after: c, coalescingKey: "name")
        history.endCoalescing()
        history.record(before: c, after: d, coalescingKey: "name")
        #expect(history.undo(current: d) == c)
        #expect(history.undo(current: c) == a)
        #expect(!history.canUndo)
        #expect(history.redo(current: a) == c)
        #expect(history.redo(current: c) == d)
    }

    @Test("Different, nil or discontinuous coalescing keys never absorb another edit")
    func coalescingBoundaries() {
        let a = fixture()
        let b = renamed(a, "B")
        let c = renamed(a, "C")
        let d = renamed(a, "D")
        for secondKey: String? in [nil, "different-field"] {
            var history = SavedGroupEditHistory()
            history.record(before: a, after: b, coalescingKey: "name")
            history.record(before: b, after: c, coalescingKey: secondKey)
            #expect(history.undo(current: c) == b)
            #expect(history.undo(current: b) == a)
        }
        var discontinuous = SavedGroupEditHistory()
        discontinuous.record(before: a, after: b, coalescingKey: "name")
        discontinuous.record(before: c, after: d, coalescingKey: "name")
        #expect(discontinuous.undo(current: d) == c)
    }

    @Test("Undo and redo terminate coalescing even when the next edit uses the same key")
    func undoRedoBoundary() {
        let a = fixture()
        let b = renamed(a, "B")
        let c = renamed(a, "C")
        var history = SavedGroupEditHistory()
        history.record(before: a, after: b, coalescingKey: "name")
        #expect(history.undo(current: b) == a)
        #expect(history.redo(current: a) == b)
        history.record(before: b, after: c, coalescingKey: "name")
        #expect(history.undo(current: c) == b)
        #expect(history.undo(current: b) == a)
    }

    @Test("A coalesced round trip removes its empty step without absorbing earlier edits")
    func coalescedRoundTrip() {
        let a = fixture()
        let b = renamed(a, "B")
        let c = renamed(a, "C")
        let d = renamed(a, "D")
        var history = SavedGroupEditHistory()
        history.record(before: a, after: b)
        history.record(before: b, after: c, coalescingKey: "color")
        history.record(before: c, after: b, coalescingKey: "color")
        history.record(before: b, after: d, coalescingKey: "color")
        #expect(history.undo(current: d) == b)
        #expect(history.undo(current: b) == a)
        #expect(!history.canUndo)
    }

    private func renamed(_ group: SavedGroup, _ name: String) -> SavedGroup {
        var result = group
        result.name = name
        return result
    }

    private func fixture() -> SavedGroup {
        SavedGroup(name: "Everyday", items: [
            .action(name: "Maps", displayName: "Home"),
            .folder(name: "Left", children: [
                .folder(name: "Nested", children: [.action(name: "Calendar", displayName: "Meetings")]),
                .action(name: "Camera", displayName: "Photos"),
            ]),
            .folder(name: "Right", children: [.action(name: "Mail")]),
            .spacer(),
        ], updatedAt: Date(timeIntervalSince1970: 1_000),
                    appearance: .init(grid: .four, iconSize: .large, plate: .gradient, tintHex: "#AA00FF"))
    }
}
